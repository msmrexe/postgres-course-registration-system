# Smart Course Registration System (PostgreSQL)

This project simulates a smart university course registration system within a PostgreSQL database. It uses advanced PL/pgSQL functions, views, and recursive queries to enforce complex business rules, such as prerequisite checking, time conflict detection, and section capacity management.

This project was developed from a series of "Mathematical Databases" course homework assignments to create a single, cohesive application.

## Features

* **Recursive Prerequisite Enforcement:** Automatically checks if a student has successfully passed all direct and indirect prerequisites for a course before registration.
* **Time Conflict Detection:** Prevents a student from registering for two sections that share the same time slot in a given semester.
* **Section Capacity Management:** Enforces classroom capacity, preventing registration in sections that are already full.
* **Atomic Registration Function:** A main `udf_attempt_registration(...)` function orchestrates all checks. If any check fails, the registration is rolled back, and an informative error message is returned.
* **Course Drop Functionality:** A `udf_drop_course(...)` function that safely removes a student from a course and updates their total credits.
* **Helper Views:** Includes useful views like `v_available_sections` (showing sections with open seats) and `v_student_schedule` (showing a student's schedule with times).

## Database Concepts Showcased

* **Advanced PL/pgSQL:** Writing complex stored functions and procedures with parameters, conditional logic (IF/ELSE), and robust error handling (`RAISE EXCEPTION`, `BEGIN/EXCEPTION` blocks).
* **Recursive Queries:** Using `WITH RECURSIVE` to traverse the prerequisite graph.
* **Data Integrity:** Enforcing complex business rules at the database level, ensuring data remains consistent.
* **Complex SQL:** Writing queries with multi-table joins, subqueries, `INTERSECT`, `EXCEPT`, and aggregation functions.
* **Database Views:** Using `CREATE VIEW` to abstract complex queries and simplify logic for other functions.
* **Transactions:** Using `BEGIN`, `COMMIT`, and `ROLLBACK` to ensure atomic operations.

---

## How It Works

The system is built on two pillars: the database schema (the tables) and the business logic (the functions and views).

### 1. Database Schema Overview

The logic primarily revolves around these key tables:

* **`student`**: Stores student information (ID, name, department, total credits).
* **`course`**: Stores course definitions, including `course_id`, `title`, and `credits`.
* **`prereq`**: A simple mapping table with two columns: `course_id` and `prereq_id`. This table defines the prerequisite graph (e.g., 'CS-347' requires 'CS-101').
* **`section`**: Represents a specific offering of a `course` in a given `semester` and `year`. It links to a `classroom` (for capacity) and a `time_slot_id` (for scheduling).
* **`time_slot`**: Defines the actual days (M, T, W, R, F) and times for a given `time_slot_id`.
* **`classroom`**: Stores building/room information and, most importantly, the `capacity` of that room.
* **`takes`**: This is the central transaction table. An entry here signifies that a `student` has taken or is currently taking a `section`. It stores the student's `grade`. A `NULL` grade indicates the course is in progress.

### 2. Core Logic and Functions

The logic is implemented in PL/pgSQL functions, which act as a smart API for the database.

#### Helper Views and Functions (`02_views_and_helpers.sql`)

These are created first to simplify the main logic:

* **`udf_convert_grade_to_points(grade)`**: A helper function that converts letter grades ('A', 'A-', 'F', etc.) into numeric grade points (4.0, 3.7, 0.0). This is crucial for defining what a "passing" grade is (any grade point > 0.0).
* **`v_student_grade_points`**: A view built on `takes` that automatically includes the numeric grade points for every course a student has taken.
* **`v_section_enrollment`**: A simple view that `COUNT`s the number of students enrolled in every section.
* **`v_available_sections`**: A powerful view that joins `section`, `classroom`, and `v_section_enrollment` to show a list of all sections that still have `seats_available > 0`.

#### Main Registration Logic (`03_registration_logic.sql`)

These functions perform the actual registration checks:

* **`udf_check_prerequisites(student_id, course_id)`**:
    1.  Uses a `WITH RECURSIVE` query to find *all* direct and indirect prerequisites for the target `course_id` by traversing the `prereq` table.
    2.  It then finds all courses the student has *passed* (grade point > 0.0) by querying the `v_student_grade_points` view.
    3.  It compares the two lists. If the list of prerequisites is not fully contained within the list of passed courses, the function returns `FALSE`.

* **`udf_check_time_conflict(student_id, ...)`**:
    1.  Finds the `time_slot_id` for the new section the student wants to register for.
    2.  Finds all `time_slot_id`s for courses the student is *already* registered for in the *same semester and year*.
    3.  Uses `INTERSECT` to see if there is any overlap between the new time slot and the existing ones. If there is, it returns `FALSE`.

* **`udf_check_capacity(...)`**:
    * This function is now very simple: it just checks if the target section `EXISTS` in the `v_available_sections` view. If it's not in that view, it's full, and the function returns `FALSE`.

* **`udf_attempt_registration(student_id, ...)`**:
    * This is the main "orchestrator" function. It wraps all checks into a single transaction.
    1.  Checks if the student is already registered for the course in the same semester.
    2.  Calls `udf_check_prerequisites`. If it fails, returns an error.
    3.  Calls `udf_check_time_conflict`. If it fails, returns an error.
    4.  Calls `udf_check_capacity`. If it fails, returns an error.
    5.  If all checks pass, it `INSERT`s a new record into the `takes` table (with a `NULL` grade) and `UPDATE`s the `student.tot_cred` by adding the course's `credits`.
    6.  Returns a success message.

* **`udf_drop_course(student_id, ...)`**:
    * Allows a student to drop a course. It `DELETE`s the record from `takes` **only if** the `grade IS NULL` (meaning the course is in-progress).
    * It then subtracts the course `credits` from the `student.tot_cred` table.

---

## Project Structure

```
postgres-course-registration-system/
├── .gitignore                      # Ignores system and credential files
├── LICENSE                         # MIT license file
├── README.md                       # This documentation
├── demo.sql                        # Example script showing how to use the system
└── src/
    ├── 00_schema.sql               # Main DDL script to create all tables
    ├── 01_data.sql                 # Script to insert sample data
    ├── 02_views_and_helpers.sql    # Creates helper views and functions
    └── 03_registration_logic.sql   # Creates the core functions (checks, register, drop)
```

## How to Use

1.  **Setup Database:**
    Create a new PostgreSQL database.
    ```bash
    createdb university_db
    ```

2.  **Connect to Database:**
    Use `psql` or any SQL client to connect to your new database.
    ```bash
    psql university_db
    ```

3.  **Run SQL Scripts (in order):**
    Execute the SQL scripts in the following order to build the database, load data, and create the functions.

    ```sql
    -- 1. Create the schema
    \i src/00_schema.sql
    
    -- 2. Load the sample data
    \i src/01_data.sql
    
    -- 3. Create helper views
    \i src/02_views_and_helpers.sql
    
    -- 4. Create the core registration logic
    \i src/03_registration_logic.sql
    ```

4.  **Test the System:**
    Run the `demo.sql` script to see the system in action. This script is wrapped in a `BEGIN...ROLLBACK` block, so it will not make permanent changes to your data.

    ```sql
    \i demo.sql
    ```
    You will see output for each test case, for example:
    ```
                    test_1_result
    ---------------------------------------------
     Registration successful for CS-315.
    (1 row)
    
                    test_2_result
    --------------------------------------------------
     Registration failed: Prerequisite check failed.
    (1 row)
    ```

## Example Function Call

To manually register a student, you can call the main function directly:

```sql
SELECT udf_attempt_registration(
    p_student_id := '12345',       -- Student ID
    p_course_id := 'CS-315',       -- Course ID
    p_sec_id := '1',               -- Section ID
    p_semester := 'Spring',        -- Semester
    p_year := 2018                 -- Year
);
```

---

## Author

Feel free to connect or reach out if you have any questions!

* **Maryam Rezaee**
* **GitHub:** [@msmrexe](https://github.com/msmrexe)
* **Email:** [ms.maryamrezaee@gmail.com](mailto:ms.maryamrezaee@gmail.com)

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for full details.
