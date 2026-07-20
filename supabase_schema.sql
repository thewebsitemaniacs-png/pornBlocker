-- Create profiles table linked to Supabase auth.users
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  is_premium BOOLEAN DEFAULT FALSE NOT NULL,
  is_admin BOOLEAN DEFAULT FALSE NOT NULL,
  is_supporter BOOLEAN DEFAULT FALSE NOT NULL,
  buddy_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Enable RLS for profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to profiles" 
  ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Allow users to update their own profiles" 
  ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Create random username generator function
CREATE OR REPLACE FUNCTION public.generate_random_username() 
RETURNS TEXT AS $$
DECLARE
  adjectives TEXT[] := ARRAY['Calm', 'Sleek', 'Brave', 'Gentle', 'Swift', 'Bright', 'Wise', 'Quiet', 'Active', 'Strong', 'Kind', 'Noble', 'Vibrant', 'Serene', 'Steady', 'Pearly'];
  nouns TEXT[] := ARRAY['Tiger', 'River', 'Forest', 'Mountain', 'Eagle', 'Falcon', 'Panda', 'Oak', 'Ocean', 'Wind', 'Star', 'Canyon', 'Valley', 'Glacier', 'Meadow', 'Peak'];
  adj TEXT;
  noun TEXT;
  num INT;
  res TEXT;
  is_unique BOOLEAN := false;
BEGIN
  WHILE NOT is_unique LOOP
    adj := adjectives[floor(random() * array_length(adjectives, 1) + 1)];
    noun := nouns[floor(random() * array_length(nouns, 1) + 1)];
    num := floor(random() * 9000 + 1000)::INT; -- 4-digit number between 1000 and 9999
    res := adj || noun || num::TEXT;
    
    SELECT NOT EXISTS (SELECT 1 FROM public.profiles WHERE username = res) INTO is_unique;
  END LOOP;
  RETURN res;
END;
$$ LANGUAGE plpgsql;

-- Create handler trigger for new auth.users signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username, is_premium, is_admin)
  VALUES (
    new.id,
    public.generate_random_username(),
    false,
    false
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create habit_tasks table
CREATE TABLE public.habit_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  is_completed BOOLEAN DEFAULT FALSE NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

ALTER TABLE public.habit_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own habit tasks" 
  ON public.habit_tasks FOR ALL USING (auth.uid() = user_id);

-- Create habit_logs table
CREATE TABLE public.habit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  event_type TEXT NOT NULL,
  payload JSONB DEFAULT '{}'::jsonb NOT NULL,
  logged_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

ALTER TABLE public.habit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own habit logs" 
  ON public.habit_logs FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Buddies can view linked partner logs" 
  ON public.habit_logs FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE (profiles.id = habit_logs.user_id AND profiles.buddy_id = auth.uid())
         OR (profiles.id = auth.uid() AND profiles.buddy_id = habit_logs.user_id)
    )
  );

-- Create global_keywords table
CREATE TABLE public.global_keywords (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  value TEXT UNIQUE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

ALTER TABLE public.global_keywords ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to global keywords" 
  ON public.global_keywords FOR SELECT USING (true);

CREATE POLICY "Allow admins to manage global keywords" 
  ON public.global_keywords FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE profiles.id = auth.uid() AND profiles.is_admin = true
    )
  );

-- Create global_domains table
CREATE TABLE public.global_domains (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  value TEXT UNIQUE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

ALTER TABLE public.global_domains ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to global domains" 
  ON public.global_domains FOR SELECT USING (true);

CREATE POLICY "Allow admins to manage global domains" 
  ON public.global_domains FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE profiles.id = auth.uid() AND profiles.is_admin = true
    )
  );

-- Populate with initial default keywords
INSERT INTO public.global_keywords (value) VALUES
  ('hot girls'),
  ('fuck'),
  ('sex videos'),
  ('porn'),
  ('adult'),
  ('xxx')
ON CONFLICT (value) DO NOTHING;

-- Populate with initial default domains
INSERT INTO public.global_domains (value) VALUES
  ('youtube.com'),
  ('instagram.com'),
  ('tiktok.com'),
  ('pornhub.com'),
  ('xvideos.com')
ON CONFLICT (value) DO NOTHING;

-- Create chat_messages table for supporter confessions
CREATE TABLE public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  recipient_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow users to view their own messages"
  ON public.chat_messages FOR SELECT USING (
    auth.uid() = sender_id OR auth.uid() = recipient_id
  );

CREATE POLICY "Allow users to insert messages as sender"
  ON public.chat_messages FOR INSERT WITH CHECK (
    auth.uid() = sender_id
  );
