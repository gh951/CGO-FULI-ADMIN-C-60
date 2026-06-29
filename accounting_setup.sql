-- ════════════════════════════════════════════════════════════
--  CGO-FULI · 회계 백엔드 (C-61)  —  비용 + 매출 통 + 집계 함수
--
--  구조 : signups 와 같은 보안 모델
--    · 원본 행은 외부(anon)가 직접 못 읽음 (RLS)
--    · 집계 함수(get_accounting_stats)로 '숫자(합계)' 만 나감 → admin 본서버 모드가 이걸 읽음
--    · 비용 입력은 소유자가 Supabase Table Editor 로 직접 행 추가(인증된 본인)
--      또는 이 파일 맨 아래의 INSERT 예시를 SQL Editor 에서 Run
--
--  정직 메모 : 매출(revenues)은 결제(PG) 연동 전이라 지금은 0 이다.
--    비용(expenses)만 먼저 채우면 '순지출' 추적이 진짜로 작동한다.
--    통화는 일단 ₩(KRW) 단일 기준으로 합산한다(다통화 환산은 다음 과제).
--
--  적용 : Supabase → SQL Editor → 전체 붙여넣고 Run.  여러 번 Run 해도 안전.
-- ════════════════════════════════════════════════════════════


-- ── 1) 비용 통 ──────────────────────────────────────────────
create table if not exists public.expenses (
  id         uuid primary key default gen_random_uuid(),
  category   text,                       -- 서버비 / 도메인 / API비 / 앱등록 / 카드수수료 / 법인세 / 기타
  amount     numeric not null default 0, -- 금액(원)
  currency   text not null default 'KRW',
  memo       text,                       -- 예: 'Vercel 6월'
  spent_at   timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ── 2) 매출 통 (결제 붙으면 채워짐) ─────────────────────────
create table if not exists public.revenues (
  id         uuid primary key default gen_random_uuid(),
  amount     numeric not null default 0,
  currency   text not null default 'KRW',
  country    text,
  source     text,                       -- '구독 PREMIUM' / '구독 VVIP' / 'CGO 오행 쇼핑' 등
  paid_at    timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ── 3) 값 위생 제약 (재실행 안전) ───────────────────────────
alter table public.expenses drop constraint if exists expenses_amount_nonneg;
alter table public.expenses add constraint expenses_amount_nonneg check (amount >= 0) not valid;
alter table public.expenses drop constraint if exists expenses_category_len;
alter table public.expenses add constraint expenses_category_len check (category is null or char_length(category) <= 60) not valid;

alter table public.revenues drop constraint if exists revenues_amount_nonneg;
alter table public.revenues add constraint revenues_amount_nonneg check (amount >= 0) not valid;
alter table public.revenues drop constraint if exists revenues_source_len;
alter table public.revenues add constraint revenues_source_len check (source is null or char_length(source) <= 60) not valid;

-- ── 4) RLS : 외부(anon)는 원본 직접 접근 차단 ───────────────
--   정책을 안 만들면 anon 직접 read/write 모두 거부된다.
--   소유자는 Table Editor(인증)로, 집계는 아래 함수(security definer)로 읽는다.
alter table public.expenses enable row level security;
alter table public.revenues enable row level security;

-- ── 5) 집계 함수 (PII 없음 · anon 실행 허용) ────────────────
create or replace function public.get_accounting_stats()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'month_rev', coalesce((select sum(amount) from revenues
                            where paid_at >= date_trunc('month', now())), 0),
    'month_exp', coalesce((select sum(amount) from expenses
                            where spent_at >= date_trunc('month', now())), 0),
    'by_category', (
      select coalesce(json_agg(t order by t.amt desc), '[]'::json)
      from (select coalesce(category,'(미분류)') as cat, sum(amount) as amt
            from expenses group by category) t
    ),
    'by_source', (
      select coalesce(json_agg(s order by s.amt desc), '[]'::json)
      from (select coalesce(source,'(미분류)') as src, sum(amount) as amt
            from revenues group by source) s
    ),
    'monthly', (
      select coalesce(json_agg(m order by m.m), '[]'::json)
      from (
        select to_char(g, 'YY/MM') as m,
               coalesce((select sum(amount) from revenues r
                          where date_trunc('month', r.paid_at) = g), 0) as rev,
               coalesce((select sum(amount) from expenses e
                          where date_trunc('month', e.spent_at) = g), 0) as exp
        from generate_series(date_trunc('month', now()) - interval '5 months',
                             date_trunc('month', now()), interval '1 month') g
      ) m
    )
  );
$$;

grant execute on function public.get_accounting_stats() to anon;


-- ════════════════════════════════════════════════════════════
--  ▼ (선택) 비용 한 줄 넣어보기 — 본 서버 모드 테스트용
--    앞의 '-- ' 두 글자를 떼고 값만 바꿔 Run 하면 비용 1건이 들어간다.
--    admin 회계 탭을 '본 서버'로 바꾸면 그 숫자가 반영된다.
-- ════════════════════════════════════════════════════════════
-- insert into public.expenses (category, amount, memo)
-- values ('서버비', 25000, 'Supabase nano 6월');

-- insert into public.expenses (category, amount, memo)
-- values ('도메인', 18000, 'c-go-fuli.com 연간');

-- ── 확인 : 함수가 도는지 ──
-- select public.get_accounting_stats();
