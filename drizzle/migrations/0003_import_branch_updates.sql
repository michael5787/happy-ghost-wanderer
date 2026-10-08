ALTER TABLE public.resources ADD COLUMN IF NOT EXISTS class_id uuid REFERENCES public.classes(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS resources_class_id_idx ON public.resources(class_id);
DROP POLICY IF EXISTS "Authenticated read resources" ON public.resources;
DROP POLICY IF EXISTS "Read resources scoped by class" ON public.resources;
CREATE POLICY "Read resources scoped by class"
ON public.resources FOR SELECT TO authenticated
USING (
  class_id IS NULL
  OR auth.uid() = teacher_id
  OR public.has_role(auth.uid(), 'super_admin'::public.app_role)
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.class_id = resources.class_id)
  OR EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id = resources.class_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.agenda_events TO authenticated;
GRANT ALL ON public.agenda_events TO service_role;
ALTER TABLE public.agenda_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Teachers insert agenda for their classes" ON public.agenda_events;
CREATE POLICY "Teachers insert agenda for their classes"
ON public.agenda_events FOR INSERT TO authenticated
WITH CHECK (
  (auth.uid() = teacher_id AND EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id = agenda_events.class_id))
  OR public.has_role(auth.uid(), 'super_admin'::public.app_role)
);
DROP POLICY IF EXISTS "Read agenda scoped by class" ON public.agenda_events;
CREATE POLICY "Read agenda scoped by class"
ON public.agenda_events FOR SELECT TO authenticated
USING (
  auth.uid() = teacher_id
  OR public.has_role(auth.uid(), 'super_admin'::public.app_role)
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.class_id = agenda_events.class_id)
  OR EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id = agenda_events.class_id)
);
DROP POLICY IF EXISTS "Teachers update own agenda" ON public.agenda_events;
CREATE POLICY "Teachers update own agenda"
ON public.agenda_events FOR UPDATE TO authenticated
USING (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role))
WITH CHECK (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role));
DROP POLICY IF EXISTS "Teachers delete own agenda" ON public.agenda_events;
CREATE POLICY "Teachers delete own agenda"
ON public.agenda_events FOR DELETE TO authenticated
USING (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role));

ALTER TABLE public.submissions
  ADD COLUMN IF NOT EXISTS grade numeric(5,2),
  ADD COLUMN IF NOT EXISTS graded_at timestamptz;
DROP POLICY IF EXISTS "Teachers grade their submissions" ON public.submissions;
CREATE POLICY "Teachers grade their submissions" ON public.submissions
FOR UPDATE TO authenticated
USING (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role))
WITH CHECK (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role));

REVOKE ALL ON FUNCTION public.teaches_student(uuid, uuid) FROM anon;

DROP POLICY IF EXISTS "Authenticated read resource files" ON storage.objects;
DROP POLICY IF EXISTS "Read resource files scoped by class" ON storage.objects;
CREATE POLICY "Read resource files scoped by class"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'resources'
  AND EXISTS (
    SELECT 1 FROM public.resources r
    WHERE r.file_path = storage.objects.name
      AND (
        r.class_id IS NULL
        OR r.teacher_id = auth.uid()
        OR public.has_role(auth.uid(), 'super_admin')
        OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.class_id = r.class_id)
        OR EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id = r.class_id)
      )
  )
);

CREATE TABLE IF NOT EXISTS public.evaluation_grades (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  evaluation_id uuid NOT NULL REFERENCES public.agenda_events(id) ON DELETE CASCADE,
  student_id uuid NOT NULL,
  teacher_id uuid NOT NULL,
  grade numeric(5,2) NOT NULL CHECK (grade >= 0 AND grade <= 20),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (evaluation_id, student_id)
);
CREATE INDEX IF NOT EXISTS evaluation_grades_student_idx ON public.evaluation_grades (student_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.evaluation_grades TO authenticated;
GRANT ALL ON public.evaluation_grades TO service_role;
ALTER TABLE public.evaluation_grades ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER update_evaluation_grades_updated_at BEFORE UPDATE ON public.evaluation_grades
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE POLICY "Read grades" ON public.evaluation_grades FOR SELECT TO authenticated
USING (
  auth.uid() = student_id OR auth.uid() = teacher_id
  OR public.has_role(auth.uid(), 'super_admin'::public.app_role)
  OR EXISTS (SELECT 1 FROM public.agenda_events e JOIN public.teacher_classes tc ON tc.class_id = e.class_id
             WHERE e.id = evaluation_grades.evaluation_id AND tc.teacher_id = auth.uid())
);
CREATE POLICY "Teachers write grades" ON public.evaluation_grades FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = teacher_id AND (
    public.has_role(auth.uid(), 'super_admin'::public.app_role)
    OR EXISTS (SELECT 1 FROM public.agenda_events e JOIN public.teacher_classes tc ON tc.class_id = e.class_id
               WHERE e.id = evaluation_grades.evaluation_id AND e.kind = 'evaluation' AND tc.teacher_id = auth.uid())
  )
);
CREATE POLICY "Teachers update grades" ON public.evaluation_grades FOR UPDATE TO authenticated
USING (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role))
WITH CHECK (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role));
CREATE POLICY "Teachers delete grades" ON public.evaluation_grades FOR DELETE TO authenticated
USING (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role));

CREATE TABLE public.questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  student_id uuid NOT NULL,
  teacher_id uuid,
  title text NOT NULL,
  body text,
  file_path text,
  file_name text,
  mime_type text,
  file_size bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX questions_class_idx ON public.questions (class_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.questions TO authenticated;
GRANT ALL ON public.questions TO service_role;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Read questions of own class"
ON public.questions FOR SELECT TO authenticated
USING (
  auth.uid() = student_id
  OR public.has_role(auth.uid(), 'super_admin')
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.class_id = questions.class_id)
  OR EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id = questions.class_id)
);
CREATE POLICY "Students ask questions in own class"
ON public.questions FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = student_id
  AND EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.class_id = questions.class_id)
);
CREATE POLICY "Authors update own questions"
ON public.questions FOR UPDATE TO authenticated
USING (auth.uid() = student_id) WITH CHECK (auth.uid() = student_id);
CREATE POLICY "Authors delete own questions"
ON public.questions FOR DELETE TO authenticated
USING (auth.uid() = student_id OR public.has_role(auth.uid(), 'super_admin'));
CREATE TRIGGER update_questions_updated_at BEFORE UPDATE ON public.questions
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.question_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
  teacher_id uuid NOT NULL,
  body text,
  file_path text,
  file_name text,
  mime_type text,
  file_size bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX question_answers_question_idx ON public.question_answers (question_id, created_at);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.question_answers TO authenticated;
GRANT ALL ON public.question_answers TO service_role;
ALTER TABLE public.question_answers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Read answers of visible questions"
ON public.question_answers FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.questions q
    WHERE q.id = question_answers.question_id
      AND (
        q.student_id = auth.uid()
        OR public.has_role(auth.uid(), 'super_admin')
        OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.class_id = q.class_id)
        OR EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id = q.class_id)
      )
  )
);
CREATE POLICY "Teachers answer questions of their classes"
ON public.question_answers FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = teacher_id
  AND EXISTS (
    SELECT 1 FROM public.questions q
    JOIN public.teacher_classes tc ON tc.class_id = q.class_id
    WHERE q.id = question_answers.question_id AND tc.teacher_id = auth.uid()
  )
);
CREATE POLICY "Teachers update own answers"
ON public.question_answers FOR UPDATE TO authenticated
USING (auth.uid() = teacher_id) WITH CHECK (auth.uid() = teacher_id);
CREATE POLICY "Teachers delete own answers"
ON public.question_answers FOR DELETE TO authenticated
USING (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'));
CREATE TRIGGER update_question_answers_updated_at BEFORE UPDATE ON public.question_answers
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE POLICY "Read question files of own class"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'questions'
  AND (
    owner = auth.uid()
    OR public.has_role(auth.uid(), 'super_admin')
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.class_id::text = (storage.foldername(name))[1])
    OR EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id::text = (storage.foldername(name))[1])
  )
);
CREATE POLICY "Upload question files in own class"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'questions'
  AND (
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.class_id::text = (storage.foldername(name))[1])
    OR EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id::text = (storage.foldername(name))[1])
  )
);
CREATE POLICY "Delete own question files"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'questions' AND (owner = auth.uid() OR public.has_role(auth.uid(), 'super_admin')));

CREATE OR REPLACE FUNCTION public.shares_class(_viewer uuid, _target uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles v JOIN public.profiles t ON t.class_id = v.class_id
    WHERE v.id = _viewer AND t.id = _target AND v.class_id IS NOT NULL
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles v JOIN public.teacher_classes tc ON tc.class_id = v.class_id
    WHERE v.id = _viewer AND tc.teacher_id = _target AND v.class_id IS NOT NULL
  )
$$;
REVOKE EXECUTE ON FUNCTION public.shares_class(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.shares_class(uuid, uuid) TO authenticated;
CREATE POLICY "Classmates and class teachers read profiles"
ON public.profiles FOR SELECT TO authenticated
USING (public.shares_class(auth.uid(), id));

CREATE TABLE public.chapters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  level_id uuid NOT NULL REFERENCES public.levels(id) ON DELETE CASCADE,
  name text NOT NULL,
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chapters TO authenticated;
GRANT ALL ON public.chapters TO service_role;
ALTER TABLE public.chapters ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated read chapters" ON public.chapters FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins insert chapters" ON public.chapters FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'super_admin'));
CREATE POLICY "Admins update chapters" ON public.chapters FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'super_admin'));
CREATE POLICY "Admins delete chapters" ON public.chapters FOR DELETE TO authenticated USING (public.has_role(auth.uid(), 'super_admin'));
CREATE INDEX chapters_level_idx ON public.chapters(level_id, position);
CREATE TRIGGER update_chapters_updated_at BEFORE UPDATE ON public.chapters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
ALTER TABLE public.resources ADD COLUMN IF NOT EXISTS chapter_id uuid REFERENCES public.chapters(id) ON DELETE SET NULL;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS chapter_id uuid REFERENCES public.chapters(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS resources_chapter_idx ON public.resources(chapter_id);
CREATE INDEX IF NOT EXISTS questions_chapter_idx ON public.questions(chapter_id);

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_path text;
DROP POLICY IF EXISTS "Signed-in users view avatars" ON storage.objects;
CREATE POLICY "Signed-in users view avatars" ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'avatars');
DROP POLICY IF EXISTS "Admins upload avatars" ON storage.objects;
CREATE POLICY "Admins upload avatars" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'avatars' AND public.has_role(auth.uid(), 'super_admin'));
DROP POLICY IF EXISTS "Admins update avatars" ON storage.objects;
CREATE POLICY "Admins update avatars" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'avatars' AND public.has_role(auth.uid(), 'super_admin'));
DROP POLICY IF EXISTS "Admins delete avatars" ON storage.objects;
CREATE POLICY "Admins delete avatars" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'avatars' AND public.has_role(auth.uid(), 'super_admin'));

CREATE TABLE IF NOT EXISTS public.homework_status (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  homework_id uuid NOT NULL REFERENCES public.agenda_events(id) ON DELETE CASCADE,
  student_id uuid NOT NULL,
  teacher_id uuid NOT NULL,
  done boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (homework_id, student_id)
);
CREATE INDEX IF NOT EXISTS homework_status_student_idx ON public.homework_status (student_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.homework_status TO authenticated;
GRANT ALL ON public.homework_status TO service_role;
ALTER TABLE public.homework_status ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER update_homework_status_updated_at BEFORE UPDATE ON public.homework_status
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE POLICY "Read homework status" ON public.homework_status FOR SELECT TO authenticated
USING (
  auth.uid() = student_id OR auth.uid() = teacher_id
  OR public.has_role(auth.uid(), 'super_admin'::public.app_role)
  OR EXISTS (SELECT 1 FROM public.agenda_events e JOIN public.teacher_classes tc ON tc.class_id = e.class_id
             WHERE e.id = homework_status.homework_id AND tc.teacher_id = auth.uid())
);
CREATE POLICY "Teachers write homework status" ON public.homework_status FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = teacher_id AND (
    public.has_role(auth.uid(), 'super_admin'::public.app_role)
    OR EXISTS (SELECT 1 FROM public.agenda_events e JOIN public.teacher_classes tc ON tc.class_id = e.class_id
               WHERE e.id = homework_status.homework_id AND e.kind = 'homework' AND tc.teacher_id = auth.uid())
  )
);
CREATE POLICY "Teachers update homework status" ON public.homework_status FOR UPDATE TO authenticated
USING (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role))
WITH CHECK (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role));
CREATE POLICY "Teachers delete homework status" ON public.homework_status FOR DELETE TO authenticated
USING (auth.uid() = teacher_id OR public.has_role(auth.uid(), 'super_admin'::public.app_role));

CREATE TABLE public.lesson_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL DEFAULT auth.uid(),
  class_id uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  log_date date NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lesson_logs_range CHECK (start_time >= '08:00' AND end_time <= '17:30' AND end_time > start_time),
  CONSTRAINT lesson_logs_content_len CHECK (char_length(content) BETWEEN 1 AND 5000)
);
CREATE INDEX lesson_logs_teacher_date_idx ON public.lesson_logs (teacher_id, log_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lesson_logs TO authenticated;
GRANT ALL ON public.lesson_logs TO service_role;
ALTER TABLE public.lesson_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Teachers read own logs" ON public.lesson_logs FOR SELECT TO authenticated USING (teacher_id = auth.uid());
CREATE POLICY "Teachers insert own logs" ON public.lesson_logs FOR INSERT TO authenticated WITH CHECK (teacher_id = auth.uid() AND EXISTS (SELECT 1 FROM public.teacher_classes tc WHERE tc.teacher_id = auth.uid() AND tc.class_id = lesson_logs.class_id));
CREATE POLICY "Teachers update own logs" ON public.lesson_logs FOR UPDATE TO authenticated USING (teacher_id = auth.uid()) WITH CHECK (teacher_id = auth.uid());
CREATE POLICY "Teachers delete own logs" ON public.lesson_logs FOR DELETE TO authenticated USING (teacher_id = auth.uid());
CREATE TRIGGER update_lesson_logs_updated_at BEFORE UPDATE ON public.lesson_logs FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.school_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  name text NOT NULL DEFAULT '',
  address text NOT NULL DEFAULT '',
  phone text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.school_settings TO authenticated;
GRANT ALL ON public.school_settings TO service_role;
ALTER TABLE public.school_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Signed-in read school settings" ON public.school_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins insert school settings" ON public.school_settings FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'super_admin'));
CREATE POLICY "Admins update school settings" ON public.school_settings FOR UPDATE TO authenticated USING (public.has_role(auth.uid(), 'super_admin')) WITH CHECK (public.has_role(auth.uid(), 'super_admin'));
CREATE TRIGGER update_school_settings_updated_at BEFORE UPDATE ON public.school_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();