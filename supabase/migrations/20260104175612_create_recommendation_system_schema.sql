/*
  # Create Recommendation System Schema

  1. New Tables
    - `students`
      - `id` (uuid, primary key) - Unique student identifier
      - `name` (text) - Student name
      - `email` (text, unique) - Student email
      - `interests` (text[]) - Array of interest tags (e.g., ["biology", "drawing", "technology"])
      - `grades` (jsonb) - Subject grades as JSON (e.g., {"math": 85, "biology": 90})
      - `created_at` (timestamptz) - Record creation timestamp
      - `updated_at` (timestamptz) - Record update timestamp

    - `programs`
      - `id` (uuid, primary key) - Unique program identifier
      - `name` (text) - Program name (e.g., "Landscape Architecture")
      - `description` (text) - Detailed program description
      - `tags` (text[]) - Array of relevant tags/keywords
      - `skills` (text[]) - Array of skills developed in program
      - `requirements` (jsonb) - Entry requirements (grades, prerequisites)
      - `created_at` (timestamptz) - Record creation timestamp

    - `recommendations`
      - `id` (uuid, primary key) - Unique recommendation identifier
      - `student_id` (uuid, foreign key) - Reference to student
      - `program_id` (uuid, foreign key) - Reference to program
      - `score` (float) - Recommendation score (0-1)
      - `explanation` (text) - Human-readable explanation
      - `algorithm` (text) - Algorithm used (content-based, collaborative, hybrid)
      - `created_at` (timestamptz) - When recommendation was generated

    - `feedback`
      - `id` (uuid, primary key) - Unique feedback identifier
      - `student_id` (uuid, foreign key) - Reference to student
      - `program_id` (uuid, foreign key) - Reference to program
      - `rating` (int) - User rating (1-5 stars)
      - `clicked` (boolean) - Whether user clicked to view details
      - `accepted` (boolean) - Whether user accepted/saved recommendation
      - `created_at` (timestamptz) - Feedback timestamp

  2. Security
    - Enable RLS on all tables
    - Add policies for authenticated users to:
      - Read all programs (public catalog)
      - Read/write their own student profile
      - Read their own recommendations
      - Write their own feedback

  3. Indexes
    - Create indexes on foreign keys for performance
    - Create GIN index on tags and skills arrays for fast searching
*/

-- Create students table
CREATE TABLE IF NOT EXISTS students (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  email text UNIQUE NOT NULL,
  interests text[] DEFAULT '{}',
  grades jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create programs table
CREATE TABLE IF NOT EXISTS programs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text NOT NULL,
  tags text[] DEFAULT '{}',
  skills text[] DEFAULT '{}',
  requirements jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

-- Create recommendations table
CREATE TABLE IF NOT EXISTS recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  program_id uuid NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  score float NOT NULL,
  explanation text NOT NULL,
  algorithm text NOT NULL DEFAULT 'content-based',
  created_at timestamptz DEFAULT now()
);

-- Create feedback table
CREATE TABLE IF NOT EXISTS feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  program_id uuid NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  rating int CHECK (rating >= 1 AND rating <= 5),
  clicked boolean DEFAULT false,
  accepted boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_recommendations_student ON recommendations(student_id);
CREATE INDEX IF NOT EXISTS idx_recommendations_program ON recommendations(program_id);
CREATE INDEX IF NOT EXISTS idx_feedback_student ON feedback(student_id);
CREATE INDEX IF NOT EXISTS idx_feedback_program ON feedback(program_id);

-- GIN indexes for array columns
CREATE INDEX IF NOT EXISTS idx_programs_tags ON programs USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_programs_skills ON programs USING GIN(skills);
CREATE INDEX IF NOT EXISTS idx_students_interests ON students USING GIN(interests);

-- Enable Row Level Security
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

-- Policies for students table
CREATE POLICY "Students can read own profile"
  ON students FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Students can update own profile"
  ON students FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Students can insert own profile"
  ON students FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Policies for programs table (public read)
CREATE POLICY "Anyone can read programs"
  ON programs FOR SELECT
  TO authenticated
  USING (true);

-- Policies for recommendations table
CREATE POLICY "Students can read own recommendations"
  ON recommendations FOR SELECT
  TO authenticated
  USING (student_id = auth.uid());

CREATE POLICY "Students can insert own recommendations"
  ON recommendations FOR INSERT
  TO authenticated
  WITH CHECK (student_id = auth.uid());

-- Policies for feedback table
CREATE POLICY "Students can read own feedback"
  ON feedback FOR SELECT
  TO authenticated
  USING (student_id = auth.uid());

CREATE POLICY "Students can insert own feedback"
  ON feedback FOR INSERT
  TO authenticated
  WITH CHECK (student_id = auth.uid());

CREATE POLICY "Students can update own feedback"
  ON feedback FOR UPDATE
  TO authenticated
  USING (student_id = auth.uid())
  WITH CHECK (student_id = auth.uid());