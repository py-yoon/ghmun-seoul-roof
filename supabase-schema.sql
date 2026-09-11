-- ==============================================================================
-- 서울 옥상 지도 (Seoul Rooftop Map) - Supabase 테이블 스키마
-- 용도: 옥상별 실시간 방문자 팁/댓글(roof_comments) 및 시민 새 옥상 제보(roof_reports)
-- 사용법: Supabase Dashboard -> SQL Editor에 붙여넣고 Run 실행
-- ==============================================================================

-- 1. 옥상 댓글/방문 팁 테이블 (roof_comments)
create table if not exists public.roof_comments (
  id uuid primary key default gen_random_uuid(),
  roof_id integer not null,
  nickname text not null default '익명' check (char_length(nickname) between 1 and 30),
  content text not null check (char_length(content) between 1 and 1000),
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- 인덱스 생성 (옥상별 빠른 댓글 조회를 위해)
create index if not exists idx_roof_comments_roof_id_created_at
  on public.roof_comments (roof_id, created_at desc);

-- 2. 새 옥상 시민 제보 테이블 (roof_reports)
create table if not exists public.roof_reports (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 100),
  address text not null check (char_length(address) between 1 and 200),
  floor text,
  height text,
  hours text,
  access text,
  features text[],
  view_description text,
  memo text,
  nickname text default '익명',
  status text default 'pending',
  user_id uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- 인덱스 생성
create index if not exists idx_roof_reports_created_at
  on public.roof_reports (created_at desc);

-- 3. RLS (Row Level Security) 활성화
alter table public.roof_comments enable row level security;
alter table public.roof_reports enable row level security;

-- 권한 부여
grant usage on schema public to anon, authenticated;
grant select, insert on public.roof_comments to anon, authenticated;
grant delete on public.roof_comments to authenticated;

grant select, insert on public.roof_reports to anon, authenticated;

-- 4. RLS 정책 정의

-- [roof_comments]
-- 누구나 댓글 조회 가능
drop policy if exists "누구나 옥상 댓글을 읽을 수 있음" on public.roof_comments;
create policy "누구나 옥상 댓글을 읽을 수 있음"
  on public.roof_comments for select
  using (true);

-- 누구나 댓글 작성 가능 (익명/로그인 모두 허용)
drop policy if exists "누구나 옥상 댓글을 쓸 수 있음" on public.roof_comments;
create policy "누구나 옥상 댓글을 쓸 수 있음"
  on public.roof_comments for insert
  to anon, authenticated
  with check (true);

-- 작성자 본인만 댓글 삭제 가능
drop policy if exists "자기 옥상 댓글만 지울 수 있음" on public.roof_comments;
create policy "자기 옥상 댓글만 지울 수 있음"
  on public.roof_comments for delete
  to authenticated
  using (auth.uid() = user_id);

-- [roof_reports]
-- 누구나 제보 등록 가능
drop policy if exists "누구나 새 옥상을 제보할 수 있음" on public.roof_reports;
create policy "누구나 새 옥상을 제보할 수 있음"
  on public.roof_reports for insert
  to anon, authenticated
  with check (true);

-- 누구나 제보 현황 조회 가능
drop policy if exists "누구나 제보 목록을 읽을 수 있음" on public.roof_reports;
create policy "누구나 제보 목록을 읽을 수 있음"
  on public.roof_reports for select
  using (true);

-- 5. 스팸 방지 레이트 리밋 함수 및 트리거 (동일 사용자의 10초 내 중복 댓글 방지)
create or replace function public.enforce_roof_comment_rate_limit()
returns trigger as $$
begin
  if new.user_id is not null and exists (
    select 1 from public.roof_comments
    where user_id = new.user_id
      and created_at > now() - interval '10 seconds'
  ) then
    raise exception 'rate_limited: 댓글은 10초에 한 번만 남길 수 있습니다.';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists roof_comments_rate_limit on public.roof_comments;
create trigger roof_comments_rate_limit
  before insert on public.roof_comments
  for each row execute function public.enforce_roof_comment_rate_limit();
