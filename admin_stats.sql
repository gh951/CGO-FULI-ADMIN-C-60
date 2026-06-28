-- ════════════════════════════════════════════════════
-- CGO-FULI ADMIN · C-60 : 집계 통계 함수 (개인정보 미노출)
-- 이메일·전화번호 같은 '원본'은 절대 안 나가고, '숫자(집계)'만 나갑니다.
-- → anon 키로 호출해도 안전 (가입자 목록 원본은 못 가져감)
-- Supabase > SQL Editor 에 붙여넣고 Run
-- ════════════════════════════════════════════════════

create or replace function public.get_admin_stats()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'total', (select count(*) from signups),
    'today', (select count(*) from signups where created_at >= (now() - interval '24 hours')),
    'by_country', (
      select coalesce(json_agg(t order by t.count desc), '[]'::json)
      from (select coalesce(country,'(미상)') as country, count(*) as count
            from signups group by country) t
    ),
    'by_method', (
      select coalesce(json_agg(m order by m.count desc), '[]'::json)
      from (select coalesce(method,'unknown') as method, count(*) as count
            from signups group by method) m
    ),
    'recent', (
      select coalesce(json_agg(r), '[]'::json)
      from (select method, country, created_at
            from signups order by created_at desc limit 20) r
    )
  );
$$;

-- anon(공개 키)이 이 '집계 함수'만 실행하도록 허용 (원본 테이블 직접 읽기는 여전히 차단)
grant execute on function public.get_admin_stats() to anon;
