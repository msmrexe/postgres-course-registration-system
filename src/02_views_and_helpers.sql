/*
 * ----------------------------------------------------------------------------
 * 02_views_and_helpers.sql
 *
 * Creates helper functions and views to simplify registration logic.
 * - udf_convert_grade_to_points: Converts letter grades to numeric points.
 * - v_student_grade_points: A view of the 'takes' table with numeric grades.
 * - v_section_enrollment: A view for current enrollment in each section.
 * - v_available_sections: A view showing sections with open seats.
 * - v_student_schedule: A view showing a student's schedule with times.
 * ----------------------------------------------------------------------------
 */

-- 1. Helper Function: Convert Grade to Numeric Points
-- This refines the 'conv_grade' function from the homework.
-- We define a passing grade as > 0.0 (i.e., not 'F').
CREATE OR REPLACE FUNCTION udf_convert_grade_to_points(p_grade VARCHAR(2))
RETURNS NUMERIC(2, 1)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN CASE
        WHEN p_grade = 'A'  THEN 4.0
        WHEN p_grade = 'A-' THEN 3.7
        WHEN p_grade = 'B+' THEN 3.3
        WHEN p_grade = 'B'  THEN 3.0
        WHEN p_grade = 'B-' THEN 2.7
        WHEN p_grade = 'C+' THEN 2.3
        WHEN p_grade = 'C'  THEN 2.0
        WHEN p_grade = 'C-' THEN 1.7
        WHEN p_grade = 'D+' THEN 1.3
        WHEN p_grade = 'D'  THEN 1.0
        WHEN p_grade = 'D-' THEN 0.7
        WHEN p_grade = 'F'  THEN 0.0
        ELSE NULL -- For 'NULL' or other grades
    END;
END;
$$;

-- 2. View: Student Grade Points
-- Uses the conversion function to create a numeric view of grades.
CREATE OR REPLACE VIEW v_student_grade_points AS
SELECT
    id,
    course_id,
    sec_id,
    semester,
    year,
    grade,
    udf_convert_grade_to_points(grade) AS grade_points
FROM takes;

-- 3. View: Section Enrollment
-- Calculates the current enrollment for all sections.
CREATE OR REPLACE VIEW v_section_enrollment AS
SELECT
    course_id,
    sec_id,
    semester,
    year,
    count(id) AS current_enrollment
FROM takes
GROUP BY course_id, sec_id, semester, year;

-- 4. View: Available Sections
-- Shows sections with available seats by comparing capacity to enrollment.
CREATE OR REPLACE VIEW v_available_sections AS
SELECT
    s.course_id,
    co.title,
    s.sec_id,
    s.semester,
    s.year,
    c.capacity,
    COALESCE(e.current_enrollment, 0) AS current_enrollment,
    (c.capacity - COALESCE(e.current_enrollment, 0)) AS seats_available
FROM section s
JOIN course co ON s.course_id = co.course_id
JOIN classroom c ON s.building = c.building AND s.room_number = c.room_number
LEFT JOIN v_section_enrollment e ON
    s.course_id = e.course_id AND
    s.sec_id = e.sec_id AND
    s.semester = e.semester AND
    s.year = e.year
WHERE (c.capacity - COALESCE(e.current_enrollment, 0)) > 0;

-- 5. View: Student Schedule
-- Shows a student's schedule with days and times for a given semester.
CREATE OR REPLACE VIEW v_student_schedule AS
SELECT
    t.id AS student_id,
    c.title,
    s.sec_id,
    s.semester,
    s.year,
    ts.day,
    ts.start_hr,
    ts.start_min,
    ts.end_hr,
    ts.end_min
FROM takes t
JOIN section s ON
    t.course_id = s.course_id AND
    t.sec_id = s.sec_id AND
    t.semester = s.semester AND
    t.year = s.year
JOIN course c ON s.course_id = c.course_id
JOIN time_slot ts ON s.time_slot_id = ts.time_slot_id;
