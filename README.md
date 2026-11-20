# DL CUADRA PRO

**Cuadra tu caja, todos los días. Inventario + ventas = resultados.**

Desarrollado y administrado por **DL COMPANY -TECHNOLOGY-**.

## Qué es

App web para negocios que necesitan controlar **cuántos productos venden al día** y cuánto inventario les queda. Nació del Excel de un local de venta de bebidas en la Comuna 13 (Medellín).

## Funciones

- **Vender**: punto de venta táctil. Toca productos, cobra en efectivo o QR, calcula vueltas y descuenta del inventario.
- **Inventario**: stock por producto y categoría, alertas de stock bajo/agotado, entradas de mercancía, ajuste por conteo físico, edición de precios.
- **Cierre del día**: tabla inicial · entrada · vendido · final · ventas $ (igual al Excel), efectivo / QR / gastos, efectivo en caja, anular ventas y copiar resumen para WhatsApp.
- **Nube (Supabase)**: inicio de sesión, datos compartidos entre varios celulares y sincronización en tiempo real.

## Estructura

```
index.html            App completa (HTML + CSS + JS)
legal.html            Términos y condiciones, privacidad y reembolsos
config.js             URL y clave pública de Supabase + nombre del negocio
manifest.json         Instalación en el celular (nombre e íconos)
logo.svg              Logo DL CUADRA PRO (+ icon-192/512, apple-touch-icon)
dl-company.png        Logo de DL COMPANY -TECHNOLOGY-
supabase/schema.sql   Tablas, seguridad, funciones y tiempo real
supabase/seed.sql     Productos iniciales (del Excel) + ejemplo del 3 de julio 2024
```

## Configurar la nube (Supabase, gratis)

1. Crea una cuenta en [supabase.com](https://supabase.com) → **New project** (región: *South America (São Paulo)*). Guarda la contraseña de la base de datos.
2. **SQL Editor → New query** → pega todo `supabase/schema.sql` → **Run**.
3. Nueva query → pega `supabase/seed.sql` → **Run** (carga los productos).
   - Luego, en orden: `v4-empresas.sql` (empresas, sedes y cajeros) y `v5-catalogo.sql` (catálogo común por código de barras).
4. **Authentication → Users → Add user → Create new user**: correo + contraseña, marca *Auto Confirm User*. Ese es el usuario para entrar a la app (crea uno por cada persona que venda).
5. **Authentication → Sign In / Providers** → desactiva **Allow new users to sign up** (así nadie más puede crear cuentas).
6. **Project Settings → API**: copia *Project URL* y la *anon public key* y pégalas en `config.js`.

## Publicar en GitHub Pages

Repositorio → **Settings → Pages** → *Source: Deploy from a branch* → rama `main`, carpeta `/ (root)` → **Save**. En 1–2 minutos queda en `https://TU-USUARIO.github.io/NOMBRE-REPO/`.

Sin `config.js` configurado, la app funciona en **modo local** (datos solo en ese navegador).

## Hoja de ruta

- [x] Punto de venta, inventario y cierre del día
- [x] Nube con Supabase, inicio de sesión y tiempo real
- [ ] Varios negocios y roles (dueño / cajero)
- [ ] Mejoras visuales y de experiencia
- [ ] Reportes por semana / mes
- [x] Marca DL CUADRA PRO, créditos DL COMPANY y documentos legales
- [ ] Instalable en el celular (PWA completa)
