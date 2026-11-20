-- DL CUADRA PRO v3.9.0 — Catálogo común de productos por código de barras
-- Al registrar un producto nuevo con código, su nombre y categoría quedan aquí
-- para llenar automáticamente el formulario a otros negocios que escaneen el mismo código.
-- No guarda precios, costos, stock ni datos de la empresa.

create table if not exists public.catalogo (
  codigo     text primary key check (codigo ~ '^[0-9]{8,14}$'),
  nombre     text not null check (char_length(nombre) between 3 and 120),
  cat        text check (cat is null or char_length(cat) <= 40),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null,
  creado     timestamptz not null default now()
);

alter table public.catalogo enable row level security;

-- Cualquier usuario con sesión puede consultar el catálogo
drop policy if exists catalogo_leer on public.catalogo;
create policy catalogo_leer on public.catalogo
  for select to authenticated using (true);

-- Cualquier usuario con sesión puede agregar un código nuevo, a su propio nombre.
-- No hay políticas de update ni delete: lo que entra no se puede cambiar desde la app.
drop policy if exists catalogo_agregar on public.catalogo;
create policy catalogo_agregar on public.catalogo
  for insert to authenticated with check (creado_por = (select auth.uid()));
