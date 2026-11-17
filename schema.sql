-- =========================================================
--  Control de Ventas · Esquema de base de datos (Supabase)
--  Pegar completo en: Supabase → SQL Editor → New query → Run
-- =========================================================

-- ---------- Tablas ----------
create table if not exists public.productos (
  id      text primary key,
  nombre  text    not null,
  cat     text    not null default 'Otros',
  precio  integer not null default 0 check (precio >= 0),
  stock   integer not null default 0,
  orden   integer not null default 999,
  activo  boolean not null default true,
  creado  timestamptz not null default now()
);

create table if not exists public.movimientos (
  id      uuid primary key default gen_random_uuid(),
  tipo    text not null check (tipo in ('venta','entrada','ajuste','gasto')),
  fecha   date not null,
  ts      timestamptz not null default now(),
  -- venta
  items   jsonb,
  total   integer,
  metodo  text check (metodo in ('efectivo','qr')),
  -- entrada / ajuste
  pid     text references public.productos(id),
  nombre  text,
  cant    integer,
  -- gasto
  descr   text,
  valor   integer,
  usuario uuid default auth.uid()
);
create index if not exists movimientos_fecha_idx on public.movimientos (fecha);

-- ---------- Seguridad (solo usuarios con sesión) ----------
alter table public.productos   enable row level security;
alter table public.movimientos enable row level security;

drop policy if exists "usuarios leen productos"    on public.productos;
drop policy if exists "usuarios editan productos"  on public.productos;
drop policy if exists "usuarios leen movimientos"  on public.movimientos;
drop policy if exists "usuarios editan movimientos" on public.movimientos;

create policy "usuarios leen productos"    on public.productos   for select to authenticated using (true);
create policy "usuarios editan productos"  on public.productos   for all    to authenticated using (true) with check (true);
create policy "usuarios leen movimientos"  on public.movimientos for select to authenticated using (true);
create policy "usuarios editan movimientos" on public.movimientos for all   to authenticated using (true) with check (true);

-- ---------- Operaciones atómicas (el stock nunca queda descuadrado) ----------

-- Registrar una venta: guarda la venta y descuenta el stock en un solo paso.
-- p_items = [{"pid":"agua","cant":2}, ...]  (el precio se toma de la base de datos)
create or replace function public.registrar_venta(p_fecha date, p_items jsonb, p_metodo text)
returns uuid language plpgsql security invoker as $$
declare
  v_id uuid; v_total integer := 0; v_items jsonb := '[]'::jsonb; it jsonb; p public.productos;
begin
  if jsonb_array_length(p_items) = 0 then raise exception 'Venta vacía'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into p from public.productos where id = it->>'pid' for update;
    if not found then raise exception 'Producto % no existe', it->>'pid'; end if;
    if (it->>'cant')::int <= 0 then raise exception 'Cantidad inválida'; end if;
    update public.productos set stock = stock - (it->>'cant')::int where id = p.id;
    v_total := v_total + p.precio * (it->>'cant')::int;
    v_items := v_items || jsonb_build_object('pid', p.id, 'nombre', p.nombre, 'cant', (it->>'cant')::int, 'precio', p.precio);
  end loop;
  insert into public.movimientos (tipo, fecha, items, total, metodo)
  values ('venta', p_fecha, v_items, v_total, p_metodo) returning id into v_id;
  return v_id;
end $$;

-- Anular una venta: devuelve las unidades al inventario y borra la venta.
create or replace function public.anular_venta(p_id uuid)
returns void language plpgsql security invoker as $$
declare m public.movimientos; it jsonb;
begin
  select * into m from public.movimientos where id = p_id and tipo = 'venta' for update;
  if not found then raise exception 'Venta no encontrada'; end if;
  for it in select * from jsonb_array_elements(m.items) loop
    update public.productos set stock = stock + (it->>'cant')::int where id = it->>'pid';
  end loop;
  delete from public.movimientos where id = p_id;
end $$;

-- Entrada de mercancía: suma unidades.
create or replace function public.registrar_entrada(p_pid text, p_cant integer, p_fecha date)
returns void language plpgsql security invoker as $$
declare p public.productos;
begin
  if p_cant <= 0 then raise exception 'Cantidad inválida'; end if;
  update public.productos set stock = stock + p_cant where id = p_pid returning * into p;
  if not found then raise exception 'Producto no existe'; end if;
  insert into public.movimientos (tipo, fecha, pid, nombre, cant) values ('entrada', p_fecha, p.id, p.nombre, p_cant);
end $$;

-- Conteo físico: deja el stock en el valor contado y registra la diferencia.
create or replace function public.ajustar_stock(p_pid text, p_contado integer, p_fecha date)
returns integer language plpgsql security invoker as $$
declare p public.productos; d integer;
begin
  if p_contado < 0 then raise exception 'Conteo inválido'; end if;
  select * into p from public.productos where id = p_pid for update;
  if not found then raise exception 'Producto no existe'; end if;
  d := p_contado - p.stock;
  if d <> 0 then
    update public.productos set stock = p_contado where id = p_pid;
    insert into public.movimientos (tipo, fecha, pid, nombre, cant) values ('ajuste', p_fecha, p.id, p.nombre, d);
  end if;
  return d;
end $$;

grant execute on function public.registrar_venta(date, jsonb, text) to authenticated;
grant execute on function public.anular_venta(uuid)                  to authenticated;
grant execute on function public.registrar_entrada(text, integer, date) to authenticated;
grant execute on function public.ajustar_stock(text, integer, date)  to authenticated;
revoke execute on function public.registrar_venta(date, jsonb, text) from anon;
revoke execute on function public.anular_venta(uuid)                  from anon;
revoke execute on function public.registrar_entrada(text, integer, date) from anon;
revoke execute on function public.ajustar_stock(text, integer, date)  from anon;

-- ---------- Tiempo real (los celulares se sincronizan solos) ----------
do $$ begin
  begin alter publication supabase_realtime add table public.productos;   exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.movimientos; exception when duplicate_object then null; end;
end $$;
