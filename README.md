# APP CARD — MVP sin coste inicial

MVP web preparado para GitHub Pages (frontend), Supabase Free (usuarios y PostgreSQL) y GitHub Actions (sincronización desde Google Drive).

## Inicio local

1. Crear un proyecto gratuito en Supabase.
2. Ejecutar `supabase/migrations/001_initial.sql` en el SQL Editor.
3. Copiar `.env.example` a `.env.local` y completar los valores.
4. Ejecutar `npm install` y `npm run dev`.

## Primer administrador

Crear el primer usuario en Supabase Authentication y ejecutar:

```sql
update public.profiles set role = 'ADMIN'
where email = 'tu-correo@example.com';
```

## Secretos para sincronizar Drive

- `APP_CARD_SUPABASE_URL`
- `APP_CARD_SUPABASE_SERVICE_ROLE_KEY`
- `APP_CARD_GOOGLE_SERVICE_ACCOUNT_JSON`

Compartir los dos Markdown con el correo de la cuenta de servicio como lector.

## Variables para GitHub Pages

- `APP_CARD_SUPABASE_URL`
- `APP_CARD_SUPABASE_ANON_KEY`

No subir `.env`, credenciales de Google ni la clave `service_role`.

Este repositorio independiente se publica en GitHub Pages mediante los workflows incluidos en `.github/workflows`.

La guía paso a paso está en [CONFIGURACION_GRATUITA.md](CONFIGURACION_GRATUITA.md).
