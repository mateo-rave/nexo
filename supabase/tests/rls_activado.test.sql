-- Comprobaciones globales de seguridad del esquema.
-- No necesita datos: revisa el catálogo de PostgreSQL.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select is_empty(
  $$select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity$$,
  'todas las tablas de public tienen RLS activado'
);

select is_empty(
  $$select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p', 'v', 'm')
      and has_table_privilege('anon', c.oid, 'select, insert, update, delete, truncate, references, trigger')$$,
  'anon no tiene ningún permiso sobre tablas ni vistas de public'
);

-- Se excluyen solo las funciones que devuelven trigger o event_trigger: se
-- ejecutan mediante su trigger y PostgreSQL no permite llamarlas directamente,
-- así que no son RPC. En nexo-dev existe public.rls_auto_enable() (RLS
-- automático de Supabase, ver ADR-0004), que conserva execute para PUBLIC y
-- daría un falso positivo.
select is_empty(
  $$select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'privado')
      and p.prorettype not in (
        'pg_catalog.trigger'::pg_catalog.regtype,
        'pg_catalog.event_trigger'::pg_catalog.regtype
      )
      and has_function_privilege('anon', p.oid, 'execute')$$,
  'anon no puede ejecutar ninguna función invocable de public ni de privado'
);

select ok(
  not has_schema_privilege('anon', 'privado', 'usage'),
  'anon no tiene acceso al esquema privado'
);

select is_empty(
  $$select p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'privado')
      and p.prosecdef
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%'
      )$$,
  'toda función security definer fija su search_path'
);

select ok(
  not has_table_privilege('authenticated', 'public.membresias', 'insert, update, delete, truncate'),
  'authenticated no puede escribir directamente en membresias'
);

select ok(
  not has_table_privilege('authenticated', 'public.auditoria', 'insert, update, delete, truncate'),
  'authenticated no puede escribir directamente en auditoria'
);

select ok(
  not has_table_privilege('authenticated', 'public.organizaciones', 'insert, delete, truncate'),
  'authenticated no puede crear ni borrar organizaciones directamente'
);

select * from finish();
rollback;
