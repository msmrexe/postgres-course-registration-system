/*
 * ----------------------------------------------------------------------------
 * demo.sql
 *
 * This script demonstrates the functionality of the Smart Registration System.
 * Run this after loading the schema, data, and functions.
 * ----------------------------------------------------------------------------
 */

-- Make sure to run this in a transaction so we can roll back our tests
BEGIN;

-- ----------------------------------------------------------------------------
-- TEST CASE 1: SUCCESSFUL REGISTRATION
--
-- Student '45678' (Levy) wants to register for 'CS-315' (Robotics) in Spring 2018.
-- Prereq: 'CS-101'.
-- Check: Levy failed 'CS-101' in Fall 2017 ('F') but passed it in Spring 2018 ('B+').
--        The prereq check should PASS.
-- Time: 'CS-315' is time_slot 'D'. Levy is taking 'CS-319' (slot 'B') and 'CS-101' (slot 'F').
--       No conflict. The time check should PASS.
-- Capacity: 'CS-315' is in Watson 120 (Cap 50). 'takes' shows 2 students ('12345', '98765').
--           The capacity check should PASS.
--
-- EXPECTED: SUCCESS
-- ----------------------------------------------------------------------------
SELECT udf_attempt_registration('45678', 'CS-315', '1', 'Spring', '2018') AS test_1_result;


-- ----------------------------------------------------------------------------
-- TEST CASE 2: FAILED (PREREQUISITE)
--
-- Student '70557' (Snow) has 0 credits and has taken no courses.
-- Wants to register for 'CS-315' (Robotics).
-- Prereq: 'CS-101'.
-- Check: Snow has not passed 'CS-101'.
--
-- EXPECTED: FAILED (Prerequisite check failed)
-- ----------------------------------------------------------------------------
SELECT udf_attempt_registration('70557', 'CS-315', '1', 'Spring', '2018') AS test_2_result;


-- ----------------------------------------------------------------------------
-- TEST CASE 3: FAILED (TIME CONFLICT)
--
-- Student '12345' (Shankar) is already registered for 'CS-315' in Spring 2018.
-- 'CS-315' is in time_slot 'D'.
-- Now, Shankar tries to register for 'MU-199' in Spring 2018.
-- 'MU-199' is also in time_slot 'D'.
--
-- EXPECTED: FAILED (Time conflict detected)
-- ----------------------------------------------------------------------------
SELECT udf_attempt_registration('12345', 'MU-199', '1', 'Spring', '2018') AS test_3_result;


-- ----------------------------------------------------------------------------
-- TEST CASE 4: FAILED (CAPACITY)
--
-- Let's test the 'HIS-351' section (Spring 2018) in Painter 514.
-- Classroom 'Painter 514' has a capacity of 10.
-- The data file already has one student ('19991') registered.
--
-- First, let's manually reduce the capacity to 1 to make it full.
UPDATE classroom SET capacity = 1
WHERE building = 'Painter' AND room_number = '514';

-- Now, student '54321' (Williams) tries to register for this full section.
-- Prereq: None.
-- Time: 'HIS-351' is slot 'C'. Williams is in 'CS-190' (slot 'A') and 'CS-101' (slot 'A-').
--       No, 'CS-101' was Fall 2017. 'CS-190' was Spring 2017.
--       Let's check 'takes': Williams is not registered for anything in Spring 2018.
--       No conflict.
-- Capacity: Capacity is 1, enrollment is 1. The check should FAIL.
--
-- EXPECTED: FAILED (Section is full)
-- ----------------------------------------------------------------------------
SELECT udf_attempt_registration('54321', 'HIS-351', '1', 'Spring', '2018') AS test_4_result;


-- ----------------------------------------------------------------------------
-- TEST CASE 5: DROP COURSE
--
-- Let's have student '98988' (Tanaka) drop 'BIO-301' (Summer 2018).
-- This 'takes' record has a NULL grade, so it should be droppable.
--
-- EXPECTED: SUCCESS (Successfully dropped course)
-- ----------------------------------------------------------------------------
SELECT udf_drop_course('98988', 'BIO-301', '1', 'Summer', '2018') AS test_5_result;

-- Check that the student's 'takes' record is gone
SELECT * FROM takes
WHERE id = '98988' AND course_id = 'BIO-301';


-- Roll back all our test changes
ROLLBACK;
