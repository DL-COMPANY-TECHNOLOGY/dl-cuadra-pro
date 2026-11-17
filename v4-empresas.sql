-- =====================================================================
--  DL CUADRA PRO v2 · Empresas, sedes, dueño y cajeros (PIN)
--  Ejecutar UNA vez en Supabase → SQL Editor (selector en "Database").
--  Se puede volver a ejecutar sin dañar nada.
--  Requiere la app v2 (las funciones de la v1.1 se reemplazan).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Tablas nuevas
-- ---------------------------------------------------------------------
create table if not exists public.empresas (
  id      uuid primary key default gen_random_uuid(),
  nombre  text not null,
  nit     text not null,
  plan    text not null default 'pro',
  activa  boolean not null default true,
  creado  timestamptz not null default now()
);
create unique index if not exists empresas_nit_unico
  on public.empresas ((regexp_replace(nit, '[^0-9]', '', 'g')));

create table if not exists public.sedes (
  id         uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nombre     text not null,
  activa     boolean not null default true,
  orden      integer not null default 0,
  creado     timestamptz not null default now()
);
create index if not exists sedes_empresa_idx on public.sedes (empresa_id);

create table if not exists public.cajeros (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id) on delete cascade,
  usuario         text not null,
  pin_hash        text not null,
  activo          boolean not null default true,
  intentos        integer not null default 0,
  bloqueado_hasta timestamptz,
  creado          timestamptz not null default now()
);
create unique index if not exists cajeros_usuario_unico
  on public.cajeros (empresa_id, lower(btrim(usuario)));

create table if not exists public.cajero_sedes (
  cajero_id uuid not null references public.cajeros(id) on delete cascade,
  sede_id   uuid not null references public.sedes(id) on delete cascade,
  primary key (cajero_id, sede_id)
);

create table if not exists public.perfiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  rol        text not null check (rol in ('dueno', 'cajero')),
  cajero_id  uuid references public.cajeros(id) on delete cascade,
  creado     timestamptz not null default now()
);
create index if not exists perfiles_empresa_idx on public.perfiles (empresa_id);

create table if not exists public.login_fallos (
  id         bigint generated always as identity primary key,
  empresa_id uuid,
  ts         timestamptz not null default now()
);
create index if not exists login_fallos_idx on public.login_fallos (empresa_id, ts);

-- ---------------------------------------------------------------------
-- 2. Funciones de apoyo (quién soy, a qué empresa y sedes tengo acceso)
-- ---------------------------------------------------------------------
create or replace function public.hoy() returns date
language sql stable as $$ select (now() at time zone 'America/Bogota')::date $$;

create or replace function public.mi_empresa() returns uuid
language sql stable security definer set search_path = public as $$
  select p.empresa_id from perfiles p
  left join cajeros c on c.id = p.cajero_id
  where p.user_id = auth.uid() and (p.rol = 'dueno' or c.activo)
$$;

create or replace function public.es_dueno() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where user_id = auth.uid() and rol = 'dueno')
$$;

create or replace function public.mi_cajero() returns uuid
language sql stable security definer set search_path = public as $$
  select p.cajero_id from perfiles p join cajeros c on c.id = p.cajero_id
  where p.user_id = auth.uid() and c.activo
$$;

create or replace function public.mi_nombre() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(c.usuario, 'Dueño') from perfiles p
  left join cajeros c on c.id = p.cajero_id where p.user_id = auth.uid()
$$;

create or replace function public.puede_sede(s uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from sedes x join perfiles p on p.empresa_id = x.empresa_id
    where x.id = s and p.user_id = auth.uid()
      and (p.rol = 'dueno'
           or (x.activa and exists (
                 select 1 from cajero_sedes cs join cajeros c on c.id = cs.cajero_id
                 where cs.sede_id = s and cs.cajero_id = p.cajero_id and c.activo)))
  )
$$;

create or replace function public.norm_txt(t text) returns text
language sql immutable as $$
  select regexp_replace(translate(lower(btrim(coalesce(t, ''))), 'áéíóúüñàèìòù', 'aeiouunaeiou'), '\s+', ' ', 'g')
$$;

-- ---------------------------------------------------------------------
-- 3. Columnas nuevas en las tablas existentes
-- ---------------------------------------------------------------------
alter table public.productos   add column if not exists empresa_id uuid references public.empresas(id) on delete cascade;
alter table public.movimientos add column if not exists empresa_id uuid references public.empresas(id) on delete cascade;
alter table public.movimientos add column if not exists sede_id    uuid references public.sedes(id) on delete set null;
alter table public.movimientos add column if not exists cajero_id  uuid references public.cajeros(id) on delete set null;
alter table public.movimientos add column if not exists por        text;
alter table public.ajustes     add column if not exists empresa_id uuid references public.empresas(id) on delete cascade;

create table if not exists public.inventario (
  empresa_id  uuid not null references public.empresas(id) on delete cascade,
  sede_id     uuid not null references public.sedes(id) on delete cascade,
  producto_id text not null,
  stock       integer not null default 0,
  actualizado timestamptz not null default now(),
  primary key (sede_id, producto_id)
);
create index if not exists inventario_empresa_idx on public.inventario (empresa_id);

-- ---------------------------------------------------------------------
-- 4. Migrar los datos actuales a la primera empresa y su sede principal
-- ---------------------------------------------------------------------
do $$
declare e uuid; s uuid; n text;
begin
  if not exists (select 1 from public.empresas) then
    select valor into n from public.ajustes where clave = 'negocio' limit 1;
    insert into public.empresas (nombre, nit) values (coalesce(nullif(btrim(n), ''), 'Mi empresa'), '0') returning id into e;
    insert into public.sedes (empresa_id, nombre) values (e, 'Sede principal') returning id into s;
    update public.productos   set empresa_id = e where empresa_id is null;
    update public.movimientos set empresa_id = e, sede_id = coalesce(sede_id, s) where empresa_id is null;
    update public.ajustes     set empresa_id = e where empresa_id is null;
    insert into public.perfiles (user_id, empresa_id, rol)
      select id, e, 'dueno' from auth.users on conflict (user_id) do nothing;
  end if;
  -- el stock que estaba en productos pasa al inventario de la sede principal
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'productos' and column_name = 'stock') then
    insert into public.inventario (empresa_id, sede_id, producto_id, stock)
      select p.empresa_id,
             (select id from public.sedes x where x.empresa_id = p.empresa_id order by orden, creado limit 1),
             p.id, p.stock
      from public.productos p
    on conflict (sede_id, producto_id) do nothing;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Llaves por empresa (dos empresas pueden tener el producto "agua")
-- ---------------------------------------------------------------------
alter table public.productos   alter column empresa_id set default public.mi_empresa();
alter table public.movimientos alter column empresa_id set default public.mi_empresa();
alter table public.ajustes     alter column empresa_id set default public.mi_empresa();
alter table public.productos   alter column empresa_id set not null;
alter table public.movimientos alter column empresa_id set not null;
alter table public.ajustes     alter column empresa_id set not null;

do $$
begin
  alter table public.movimientos drop constraint if exists movimientos_pid_fkey;
  if exists (select 1 from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
             where c.conname = 'productos_pkey' group by c.oid having count(*) = 1) then
    alter table public.productos drop constraint productos_pkey;
    alter table public.productos add primary key (empresa_id, id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'movimientos_producto_fk') then
    alter table public.movimientos add constraint movimientos_producto_fk
      foreign key (empresa_id, pid) references public.productos (empresa_id, id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'inventario_producto_fk') then
    alter table public.inventario add constraint inventario_producto_fk
      foreign key (empresa_id, producto_id) references public.productos (empresa_id, id) on delete cascade;
  end if;
  if exists (select 1 from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
             where c.conname = 'ajustes_pkey' group by c.oid having count(*) = 1) then
    alter table public.ajustes drop constraint ajustes_pkey;
    alter table public.ajustes add primary key (empresa_id, clave);
  end if;
end $$;

drop index if exists public.productos_codigo_unico;
create unique index if not exists productos_codigo_empresa
  on public.productos (empresa_id, codigo) where codigo is not null and codigo <> '';
create index if not exists movimientos_empresa_fecha_idx on public.movimientos (empresa_id, fecha);

alter table public.productos drop column if exists stock;

-- ---------------------------------------------------------------------
-- 6. Seguridad por empresa y por rol (RLS)
-- ---------------------------------------------------------------------
alter table public.empresas     enable row level security;
alter table public.sedes        enable row level security;
alter table public.cajeros      enable row level security;
alter table public.cajero_sedes enable row level security;
alter table public.perfiles     enable row level security;
alter table public.inventario   enable row level security;
alter table public.login_fallos enable row level security;

-- quitar las reglas abiertas de la v1
drop policy if exists "usuarios leen productos"     on public.productos;
drop policy if exists "usuarios editan productos"   on public.productos;
drop policy if exists "usuarios leen movimientos"   on public.movimientos;
drop policy if exists "usuarios editan movimientos" on public.movimientos;
drop policy if exists "usuarios leen ajustes"       on public.ajustes;
drop policy if exists "usuarios editan ajustes"     on public.ajustes;

drop policy if exists empresa_ver on public.empresas;
drop policy if exists empresa_editar on public.empresas;
create policy empresa_ver    on public.empresas for select to authenticated using (id = public.mi_empresa());
create policy empresa_editar on public.empresas for update to authenticated
  using (id = public.mi_empresa() and public.es_dueno()) with check (id = public.mi_empresa());

drop policy if exists sedes_ver on public.sedes;
drop policy if exists sedes_dueno on public.sedes;
create policy sedes_ver   on public.sedes for select to authenticated using (empresa_id = public.mi_empresa());
create policy sedes_dueno on public.sedes for all to authenticated
  using (empresa_id = public.mi_empresa() and public.es_dueno())
  with check (empresa_id = public.mi_empresa() and public.es_dueno());

drop policy if exists perfiles_ver on public.perfiles;
create policy perfiles_ver on public.perfiles for select to authenticated
  using (user_id = auth.uid() or (empresa_id = public.mi_empresa() and public.es_dueno()));

drop policy if exists cajeros_dueno on public.cajeros;
create policy cajeros_dueno on public.cajeros for all to authenticated
  using (empresa_id = public.mi_empresa() and public.es_dueno())
  with check (empresa_id = public.mi_empresa() and public.es_dueno());

drop policy if exists cajero_sedes_ver on public.cajero_sedes;
create policy cajero_sedes_ver on public.cajero_sedes for select to authenticated
  using (cajero_id = public.mi_cajero()
         or (public.es_dueno() and exists (select 1 from public.cajeros c where c.id = cajero_id and c.empresa_id = public.mi_empresa())));

drop policy if exists productos_ver on public.productos;
drop policy if exists productos_dueno on public.productos;
create policy productos_ver   on public.productos for select to authenticated using (empresa_id = public.mi_empresa());
create policy productos_dueno on public.productos for all to authenticated
  using (empresa_id = public.mi_empresa() and public.es_dueno())
  with check (empresa_id = public.mi_empresa() and public.es_dueno());

drop policy if exists inventario_ver on public.inventario;
create policy inventario_ver on public.inventario for select to authenticated
  using (empresa_id = public.mi_empresa() and (public.es_dueno() or public.puede_sede(sede_id)));

drop policy if exists movs_ver on public.movimientos;
drop policy if exists movs_gasto on public.movimientos;
drop policy if exists movs_borrar_gasto on public.movimientos;
create policy movs_ver on public.movimientos for select to authenticated
  using (empresa_id = public.mi_empresa() and (public.es_dueno() or public.puede_sede(sede_id)));
create policy movs_gasto on public.movimientos for insert to authenticated
  with check (tipo = 'gasto' and empresa_id = public.mi_empresa() and public.puede_sede(sede_id));
create policy movs_borrar_gasto on public.movimientos for delete to authenticated
  using (tipo = 'gasto' and empresa_id = public.mi_empresa()
         and (public.es_dueno() or (cajero_id = public.mi_cajero() and fecha = public.hoy())));

drop policy if exists ajustes_ver on public.ajustes;
drop policy if exists ajustes_dueno on public.ajustes;
create policy ajustes_ver   on public.ajustes for select to authenticated using (empresa_id = public.mi_empresa());
create policy ajustes_dueno on public.ajustes for all to authenticated
  using (empresa_id = public.mi_empresa() and public.es_dueno())
  with check (empresa_id = public.mi_empresa() and public.es_dueno());

-- columnas sensibles de cajeros: el PIN cifrado y los intentos nunca salen a la app
revoke all on public.cajeros from anon, authenticated;
grant select (id, empresa_id, usuario, activo, bloqueado_hasta, creado) on public.cajeros to authenticated;
grant update (usuario, activo) on public.cajeros to authenticated;
grant delete on public.cajeros to authenticated;
revoke all on public.cajero_sedes from anon, authenticated;
grant select on public.cajero_sedes to authenticated;
revoke all on public.login_fallos from anon, authenticated;
revoke insert, update, delete on public.inventario from anon, authenticated;
revoke insert, update, delete on public.perfiles  from anon, authenticated;
grant select on public.inventario, public.perfiles to authenticated;
revoke all on public.empresas, public.sedes, public.productos, public.movimientos, public.ajustes,
              public.inventario, public.perfiles from anon;

-- ---------------------------------------------------------------------
-- 7. Operaciones de inventario y ventas (atómicas y con permisos)
-- ---------------------------------------------------------------------
drop function if exists public.registrar_venta(date, jsonb, text);
drop function if exists public.anular_venta(uuid);
drop function if exists public.registrar_entrada(text, integer, date);
drop function if exists public.ajustar_stock(text, integer, date);

create or replace function public.registrar_venta(p_sede uuid, p_fecha date, p_items jsonb, p_metodo text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_emp uuid := mi_empresa(); v_id uuid; v_total integer := 0; v_items jsonb := '[]'::jsonb;
        it jsonb; p productos; v_cant integer;
begin
  if v_emp is null or not puede_sede(p_sede) then raise exception 'Sin permiso para esta sede'; end if;
  if p_metodo not in ('efectivo', 'qr') then raise exception 'Método de pago inválido'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Venta vacía'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    v_cant := (it->>'cant')::integer;
    if v_cant is null or v_cant <= 0 then raise exception 'Cantidad inválida'; end if;
    select * into p from productos where empresa_id = v_emp and id = it->>'pid' and activo;
    if not found then raise exception 'Producto % no existe', it->>'pid'; end if;
    if p.precio <= 0 then raise exception 'El producto % no tiene precio', p.nombre; end if;
    insert into inventario (empresa_id, sede_id, producto_id, stock) values (v_emp, p_sede, p.id, -v_cant)
      on conflict (sede_id, producto_id) do update set stock = inventario.stock - v_cant, actualizado = now();
    v_total := v_total + p.precio * v_cant;
    v_items := v_items || jsonb_build_object('pid', p.id, 'nombre', p.nombre, 'cant', v_cant, 'precio', p.precio);
  end loop;
  insert into movimientos (empresa_id, sede_id, tipo, fecha, items, total, metodo, usuario, cajero_id, por)
  values (v_emp, p_sede, 'venta', case when es_dueno() then coalesce(p_fecha, hoy()) else hoy() end,
          v_items, v_total, p_metodo, auth.uid(), mi_cajero(), mi_nombre())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.anular_venta(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m movimientos; it jsonb; v_emp uuid := mi_empresa();
begin
  select * into m from movimientos where id = p_id and empresa_id = v_emp and tipo = 'venta' for update;
  if not found then raise exception 'Venta no encontrada'; end if;
  if not (es_dueno() or (m.cajero_id is not null and m.cajero_id = mi_cajero() and m.fecha = hoy())) then
    raise exception 'Solo el dueño puede anular esta venta';
  end if;
  for it in select * from jsonb_array_elements(m.items) loop
    insert into inventario (empresa_id, sede_id, producto_id, stock) values (v_emp, m.sede_id, it->>'pid', (it->>'cant')::integer)
      on conflict (sede_id, producto_id) do update set stock = inventario.stock + (it->>'cant')::integer, actualizado = now();
  end loop;
  delete from movimientos where id = p_id;
end $$;

create or replace function public.registrar_entrada(p_sede uuid, p_pid text, p_cant integer, p_fecha date)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid := mi_empresa(); p productos;
begin
  if v_emp is null or not puede_sede(p_sede) then raise exception 'Sin permiso para esta sede'; end if;
  if p_cant is null or p_cant <= 0 then raise exception 'Cantidad inválida'; end if;
  select * into p from productos where empresa_id = v_emp and id = p_pid;
  if not found then raise exception 'Producto no existe'; end if;
  insert into inventario (empresa_id, sede_id, producto_id, stock) values (v_emp, p_sede, p.id, p_cant)
    on conflict (sede_id, producto_id) do update set stock = inventario.stock + p_cant, actualizado = now();
  insert into movimientos (empresa_id, sede_id, tipo, fecha, pid, nombre, cant, usuario, cajero_id, por)
  values (v_emp, p_sede, 'entrada', case when es_dueno() then coalesce(p_fecha, hoy()) else hoy() end,
          p.id, p.nombre, p_cant, auth.uid(), mi_cajero(), mi_nombre());
end $$;

create or replace function public.ajustar_stock(p_sede uuid, p_pid text, p_contado integer, p_fecha date)
returns integer language plpgsql security definer set search_path = public as $$
declare v_emp uuid := mi_empresa(); p productos; v_actual integer; d integer;
begin
  if v_emp is null or not es_dueno() or not puede_sede(p_sede) then raise exception 'Solo el dueño puede ajustar el conteo'; end if;
  if p_contado is null or p_contado < 0 then raise exception 'Conteo inválido'; end if;
  select * into p from productos where empresa_id = v_emp and id = p_pid;
  if not found then raise exception 'Producto no existe'; end if;
  insert into inventario (empresa_id, sede_id, producto_id, stock) values (v_emp, p_sede, p.id, 0)
    on conflict (sede_id, producto_id) do nothing;
  select stock into v_actual from inventario where sede_id = p_sede and producto_id = p.id for update;
  d := p_contado - v_actual;
  if d <> 0 then
    update inventario set stock = p_contado, actualizado = now() where sede_id = p_sede and producto_id = p.id;
    insert into movimientos (empresa_id, sede_id, tipo, fecha, pid, nombre, cant, usuario, por)
    values (v_emp, p_sede, 'ajuste', coalesce(p_fecha, hoy()), p.id, p.nombre, d, auth.uid(), mi_nombre());
  end if;
  return d;
end $$;

-- ---------------------------------------------------------------------
-- 8. Cajeros: crear, PIN, sedes (solo el dueño)
-- ---------------------------------------------------------------------
create or replace function public.generar_pin(p_emp uuid) returns text
language plpgsql volatile security definer set search_path = public, extensions as $$
declare v text; b bytea; i integer := 0;
begin
  loop
    i := i + 1;
    b := extensions.gen_random_bytes(2);
    v := lpad((((get_byte(b, 0) << 8) + get_byte(b, 1)) % 10000)::text, 4, '0');
    continue when v ~ '^(\d)\1{3}$' or v in ('1234','2345','3456','4567','5678','6789','0123','9876','8765','7654','6543','5432','4321','3210');
    exit when not exists (select 1 from cajeros where empresa_id = p_emp and pin_hash = extensions.crypt(v, pin_hash)) or i > 300;
  end loop;
  return v;
end $$;

create or replace function public.crear_cajero(p_usuario text, p_sedes uuid[])
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid := mi_empresa(); v_pin text; v_id uuid; v_usr text := regexp_replace(btrim(coalesce(p_usuario, '')), '\s+', ' ', 'g');
begin
  if v_emp is null or not es_dueno() then raise exception 'Solo el dueño puede crear cajeros'; end if;
  if length(v_usr) < 2 then raise exception 'Escribe el usuario del cajero'; end if;
  if exists (select 1 from cajeros where empresa_id = v_emp and lower(btrim(usuario)) = lower(v_usr)) then
    raise exception 'Ya existe un cajero con ese usuario';
  end if;
  if coalesce(array_length(p_sedes, 1), 0) = 0
     or exists (select 1 from unnest(p_sedes) s where not exists (select 1 from sedes where id = s and empresa_id = v_emp)) then
    raise exception 'Elige al menos una sede válida';
  end if;
  v_pin := generar_pin(v_emp);
  insert into cajeros (empresa_id, usuario, pin_hash) values (v_emp, v_usr, extensions.crypt(v_pin, extensions.gen_salt('bf', 8)))
  returning id into v_id;
  insert into cajero_sedes (cajero_id, sede_id) select v_id, s from unnest(p_sedes) s on conflict do nothing;
  return jsonb_build_object('id', v_id, 'usuario', v_usr, 'pin', v_pin);
end $$;

create or replace function public.regenerar_pin(p_cajero uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid := mi_empresa(); v_pin text;
begin
  if v_emp is null or not es_dueno() or not exists (select 1 from cajeros where id = p_cajero and empresa_id = v_emp) then
    raise exception 'Solo el dueño puede cambiar el PIN';
  end if;
  v_pin := generar_pin(v_emp);
  update cajeros set pin_hash = extensions.crypt(v_pin, extensions.gen_salt('bf', 8)), intentos = 0, bloqueado_hasta = null
  where id = p_cajero;
  delete from perfiles where cajero_id = p_cajero;   -- cierra las sesiones abiertas de ese cajero
  return v_pin;
end $$;

create or replace function public.sedes_de_cajero(p_cajero uuid, p_sedes uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid := mi_empresa();
begin
  if v_emp is null or not es_dueno() or not exists (select 1 from cajeros where id = p_cajero and empresa_id = v_emp) then
    raise exception 'Solo el dueño puede asignar sedes';
  end if;
  if coalesce(array_length(p_sedes, 1), 0) = 0
     or exists (select 1 from unnest(p_sedes) s where not exists (select 1 from sedes where id = s and empresa_id = v_emp)) then
    raise exception 'Elige al menos una sede válida';
  end if;
  delete from cajero_sedes where cajero_id = p_cajero;
  insert into cajero_sedes (cajero_id, sede_id) select p_cajero, s from unnest(p_sedes) s on conflict do nothing;
end $$;

-- ---------------------------------------------------------------------
-- 9. Ingreso del cajero: empresa + NIT + usuario + PIN (con bloqueo)
--    La app entra primero con un usuario anónimo de Supabase y esta
--    función lo convierte en el cajero si los datos son correctos.
-- ---------------------------------------------------------------------
create or replace function public.ingresar_cajero(p_empresa text, p_nit text, p_usuario text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare e empresas; c cajeros; v_fallos integer; v_sedes jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'sin_sesion'); end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
     and exists (select 1 from perfiles where user_id = auth.uid() and rol = 'dueno') then
    return jsonb_build_object('ok', false, 'error', 'es_dueno');
  end if;
  select * into e from empresas
  where regexp_replace(nit, '[^0-9]', '', 'g') = regexp_replace(coalesce(p_nit, ''), '[^0-9]', '', 'g')
    and norm_txt(nombre) = norm_txt(p_empresa) and activa;
  if not found then return jsonb_build_object('ok', false, 'error', 'datos'); end if;

  select count(*) into v_fallos from login_fallos where empresa_id = e.id and ts > now() - interval '15 minutes';
  if v_fallos >= 30 then return jsonb_build_object('ok', false, 'error', 'espera', 'minutos', 15); end if;

  if p_usuario is null then   -- primer paso: solo validar la empresa
    return jsonb_build_object('ok', true, 'paso', 'empresa');
  end if;

  select * into c from cajeros where empresa_id = e.id and lower(btrim(usuario)) = lower(btrim(p_usuario)) for update;
  if not found then
    insert into login_fallos (empresa_id) values (e.id);
    return jsonb_build_object('ok', false, 'error', 'pin');
  end if;
  if not c.activo then return jsonb_build_object('ok', false, 'error', 'inactivo'); end if;
  if c.bloqueado_hasta is not null and c.bloqueado_hasta > now() then
    return jsonb_build_object('ok', false, 'error', 'bloqueado',
      'minutos', ceil(extract(epoch from (c.bloqueado_hasta - now())) / 60));
  end if;
  if coalesce(p_pin, '') !~ '^\d{4}$' or c.pin_hash <> extensions.crypt(p_pin, c.pin_hash) then
    insert into login_fallos (empresa_id) values (e.id);
    if c.intentos + 1 >= 5 then
      update cajeros set intentos = 0, bloqueado_hasta = now() + interval '15 minutes' where id = c.id;
      return jsonb_build_object('ok', false, 'error', 'bloqueado', 'minutos', 15);
    end if;
    update cajeros set intentos = intentos + 1 where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'pin', 'quedan', 5 - (c.intentos + 1));
  end if;

  update cajeros set intentos = 0, bloqueado_hasta = null where id = c.id;
  insert into perfiles (user_id, empresa_id, rol, cajero_id) values (auth.uid(), e.id, 'cajero', c.id)
    on conflict (user_id) do update set empresa_id = excluded.empresa_id, rol = 'cajero', cajero_id = excluded.cajero_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre) order by s.orden, s.creado), '[]'::jsonb)
    into v_sedes
  from cajero_sedes cs join sedes s on s.id = cs.sede_id where cs.cajero_id = c.id and s.activa;
  return jsonb_build_object('ok', true, 'empresa', e.nombre, 'usuario', c.usuario, 'sedes', v_sedes);
end $$;

-- ---------------------------------------------------------------------
-- 10. Alta de una empresa nueva (lo usa DL COMPANY desde el SQL Editor)
--     Primero crea el usuario del dueño en Authentication → Users.
--     Ejemplo:  select public.crear_empresa('correo@dueno.com', 'Licorera La 13', '901234567-8');
-- ---------------------------------------------------------------------
create or replace function public.crear_empresa(p_email text, p_nombre text, p_nit text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_user uuid; e uuid;
begin
  select id into v_user from auth.users where lower(email) = lower(btrim(p_email));
  if v_user is null then raise exception 'Primero crea el usuario % en Authentication → Users', p_email; end if;
  if exists (select 1 from perfiles where user_id = v_user) then raise exception 'Ese usuario ya pertenece a una empresa'; end if;
  insert into empresas (nombre, nit) values (btrim(p_nombre), btrim(p_nit)) returning id into e;
  insert into sedes (empresa_id, nombre) values (e, 'Sede principal');
  insert into perfiles (user_id, empresa_id, rol) values (v_user, e, 'dueno');
  return e;
end $$;

-- permisos de ejecución
revoke execute on function public.generar_pin(uuid)                              from public, anon, authenticated;
revoke execute on function public.crear_empresa(text, text, text)                 from public, anon, authenticated;
revoke execute on function public.registrar_venta(uuid, date, jsonb, text)        from public, anon;
revoke execute on function public.anular_venta(uuid)                              from public, anon;
revoke execute on function public.registrar_entrada(uuid, text, integer, date)    from public, anon;
revoke execute on function public.ajustar_stock(uuid, text, integer, date)        from public, anon;
revoke execute on function public.crear_cajero(text, uuid[])                      from public, anon;
revoke execute on function public.regenerar_pin(uuid)                             from public, anon;
revoke execute on function public.sedes_de_cajero(uuid, uuid[])                   from public, anon;
revoke execute on function public.ingresar_cajero(text, text, text, text)         from public, anon;
grant execute on function public.registrar_venta(uuid, date, jsonb, text)         to authenticated;
grant execute on function public.anular_venta(uuid)                               to authenticated;
grant execute on function public.registrar_entrada(uuid, text, integer, date)     to authenticated;
grant execute on function public.ajustar_stock(uuid, text, integer, date)         to authenticated;
grant execute on function public.crear_cajero(text, uuid[])                       to authenticated;
grant execute on function public.regenerar_pin(uuid)                              to authenticated;
grant execute on function public.sedes_de_cajero(uuid, uuid[])                    to authenticated;
grant execute on function public.ingresar_cajero(text, text, text, text)          to authenticated;

-- ---------------------------------------------------------------------
-- 11. Tiempo real para las tablas nuevas
-- ---------------------------------------------------------------------
do $$ begin
  begin alter publication supabase_realtime add table public.inventario; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.sedes;      exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.empresas;   exception when duplicate_object then null; end;
end $$;
