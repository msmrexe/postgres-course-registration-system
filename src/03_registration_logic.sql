/*
 * ----------------------------------------------------------------------------
 * 03_registration_logic.sql
 *
 * Implements the core business logic for the smart registration system.
 * - udf_check_prerequisites: Recursively checks if a student has passed all prereqs.
 * - udf_check_time_conflict: Checks if a new section conflicts with a student's schedule.
 * - udf_check_capacity: Checks if a section is full.
 * - udf_attempt_registration: The main function to register a student.
 * - udf_drop_course: The main function to drop a student from a course.
 * ----------------------------------------------------------------------------
 */

-- 1. Function: Prerequisite Check (Recursive)
-- Returns TRUE if the student has passed all prerequisites for a course,
-- FALSE otherwise.
CREATE OR REPLACE FUNCTION udf_check_prerequisites(
    p_student_id student.id%TYPE,
    p_course_id course.course_id%TYPE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_missing_prereqs INT;
BEGIN
    -- This CTE recursively finds all prerequisites for the given course.
    WITH RECURSIVE all_prereqs (course_id, prereq_id) AS (
        SELECT course_id, prereq_id
        FROM prereq
        WHERE course_id = p_course_id
        UNION ALL
        SELECT p.course_id, p.prereq_id
        FROM prereq p
        JOIN all_prereqs ap ON p.course_id = ap.prereq_id
    ),
    -- This CTE finds all courses the student has passed (grade_points > 0.0).
    passed_courses AS (
        SELECT course_id
        FROM v_student_grade_points
        WHERE id = p_student_id AND grade_points > 0.0
    )
    -- We count how many prerequisites are NOT in the student's passed_courses.
    SELECT count(*)
    INTO v_missing_prereqs
    FROM (
        SELECT prereq_id FROM all_prereqs
        EXCEPT
        SELECT course_id FROM passed_courses
    ) AS missing;

    -- If the count of missing prerequisites is 0, the check passes.
    RETURN v_missing_prereqs = 0;
END;
$$;


-- 2. Function: Time Conflict Check
-- Returns TRUE if the student has NO time conflict, FALSE if a conflict exists.
CREATE OR REPLACE FUNCTION udf_check_time_conflict(
    p_student_id student.id%TYPE,
    p_new_course_id section.course_id%TYPE,
    p_new_sec_id section.sec_id%TYPE,
    p_new_semester section.semester%TYPE,
    p_new_year section.year%TYPE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_conflict_exists BOOLEAN;
BEGIN
    -- Check if the time_slot_id of the new section intersects with
    -- any time_slot_id of sections the student is already taking
    -- in the same semester and year.
    SELECT EXISTS (
        -- Time slots student is already registered for
        SELECT s.time_slot_id
        FROM takes t
        JOIN section s ON
            t.course_id = s.course_id AND
            t.sec_id = s.sec_id AND
            t.semester = s.semester AND
            t.year = s.year
        WHERE t.id = p_student_id
          AND t.semester = p_new_semester
          AND t.year = p_new_year
        
        INTERSECT
        
        -- Time slot of the new section
        SELECT s.time_slot_id
        FROM section s
        WHERE s.course_id = p_new_course_id
          AND s.sec_id = p_new_sec_id
          AND s.semester = p_new_semester
          AND s.year = p_new_year
    )
    INTO v_conflict_exists;

    -- Return TRUE if no conflict exists (v_conflict_exists is FALSE)
    RETURN NOT v_conflict_exists;
END;
$$;


-- 3. Function: Section Capacity Check
-- Returns TRUE if the section has seats available, FALSE if it's full.
CREATE OR REPLACE FUNCTION udf_check_capacity(
    p_course_id section.course_id%TYPE,
    p_sec_id section.sec_id%TYPE,
    p_semester section.semester%TYPE,
    p_year section.year%TYPE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_has_space BOOLEAN;
BEGIN
    -- We use the v_available_sections view.
    -- If a section is in this view, it has seats_available > 0.
    SELECT EXISTS (
        SELECT 1
        FROM v_available_sections
        WHERE course_id = p_course_id
          AND sec_id = p_sec_id
          AND semester = p_semester
          AND year = p_year
    )
    INTO v_has_space;

    RETURN v_has_space;
END;
$$;


-- 4. Main Function: Attempt Registration
-- Orchestrates all checks and registers a student if all pass.
-- Returns a success message or an error message.
CREATE OR REPLACE FUNCTION udf_attempt_registration(
    p_student_id student.id%TYPE,
    p_course_id section.course_id%TYPE,
    p_sec_id section.sec_id%TYPE,
    p_semester section.semester%TYPE,
    p_year section.year%TYPE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_credits course.credits%TYPE;
BEGIN
    -- Check 1: Is student already registered?
    IF EXISTS (
        SELECT 1 FROM takes
        WHERE id = p_student_id
          AND course_id = p_course_id
          AND semester = p_semester
          AND year = p_year
    ) THEN
        RETURN 'Registration failed: Student is already registered for this course.';
    END IF;

    -- Check 2: Prerequisites
    IF NOT udf_check_prerequisites(p_student_id, p_course_id) THEN
        RETURN 'Registration failed: Prerequisite check failed.';
    END IF;

    -- Check 3: Time Conflict
    IF NOT udf_check_time_conflict(p_student_id, p_course_id, p_sec_id, p_semester, p_year) THEN
        RETURN 'Registration failed: Time conflict detected with another registered section.';
    END IF;

    -- Check 4: Capacity
    IF NOT udf_check_capacity(p_course_id, p_sec_id, p_semester, p_year) THEN
        RETURN 'Registration failed: Section is full.';
    END IF;

    -- All checks passed!
    BEGIN
        -- Insert the new 'takes' record
        INSERT INTO takes(id, course_id, sec_id, semester, year, grade)
        VALUES(p_student_id, p_course_id, p_sec_id, p_semester, p_year, NULL);

        -- Update the student's total credits
        SELECT credits INTO v_credits FROM course WHERE course_id = p_course_id;
        
        UPDATE student
        SET tot_cred = tot_cred + v_credits
        WHERE id = p_student_id;

        RETURN 'Registration successful for ' || p_course_id || '.';

    EXCEPTION WHEN OTHERS THEN
        -- Catch any potential errors (e.g., foreign key violation)
        RETURN 'Registration failed: An unexpected database error occurred: ' || SQLERRM;
    END;
END;
$$;


-- 5. Function: Drop Course
-- Allows a student to drop a course they are registered for (and haven't completed).
CREATE OR REPLACE FUNCTION udf_drop_course(
    p_student_id student.id%TYPE,
    p_course_id section.course_id%TYPE,
    p_sec_id section.sec_id%TYPE,
    p_semester section.semester%TYPE,
    p_year section.year%TYPE
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_credits course.credits%TYPE;
    v_row_count INT;
BEGIN
    -- We only allow dropping courses that are in-progress (grade IS NULL)
    DELETE FROM takes
    WHERE id = p_student_id
      AND course_id = p_course_id
      AND sec_id = p_sec_id
      AND semester = p_semester
      AND year = p_year
      AND grade IS NULL;

    -- Get the number of rows affected
    GET DIAGNOSTICS v_row_count = ROW_COUNT;

    IF v_row_count > 0 THEN
        -- Course was dropped, update credits
        SELECT credits INTO v_credits FROM course WHERE course_id = p_course_id;
        
        UPDATE student
        SET tot_cred = tot_cred - v_credits
        WHERE id = p_student_id;
        
        RETURN 'Successfully dropped course ' || p_course_id || '.';
    ELSE
        RETURN 'Drop failed: Student not registered for this section or course is already graded.';
    END IF;
END;
$$;
