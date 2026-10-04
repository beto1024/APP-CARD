# Configuración gratuita del MVP

## 1. Supabase Free

1. Crear un proyecto en Supabase.
2. Abrir **SQL Editor**, pegar y ejecutar `supabase/migrations/001_initial.sql`.
3. En **Authentication > URL Configuration**, agregar la URL local y la futura URL de GitHub Pages.
4. Crear el primer usuario en **Authentication > Users**.
5. Convertirlo en administrador con la consulta indicada en `README.md`.
6. Instalar Supabase CLI y desplegar la función `admin-create-user`, o hacerlo desde el panel compatible con Edge Functions.

La clave `anon` es pública y se usa en el frontend. La clave `service_role` es secreta y solo se guarda como secreto de GitHub.

## 2. Google Cloud sin facturación

1. Crear un proyecto en Google Cloud.
2. Habilitar **Google Drive API**.
3. Crear una cuenta de servicio y descargar su JSON.
4. Compartir `verbos_aleman_A1_A2_B1.md` y `palabras_aleman.md` con el correo de la cuenta de servicio como lector.
5. Guardar el JSON completo como secreto `APP_CARD_GOOGLE_SERVICE_ACCOUNT_JSON` en GitHub.

La API de Drive para este volumen de uso no requiere comprar infraestructura. No colocar el JSON dentro del repositorio.

## 3. GitHub

En **Settings > Secrets and variables > Actions**:

### Secrets

- `APP_CARD_SUPABASE_URL`
- `APP_CARD_SUPABASE_SERVICE_ROLE_KEY`
- `APP_CARD_GOOGLE_SERVICE_ACCOUNT_JSON`

### Variables

- `APP_CARD_SUPABASE_URL`
- `APP_CARD_SUPABASE_ANON_KEY`

En **Settings > Pages**, elegir **GitHub Actions**. Ejecutar manualmente, en este orden:

1. `APP CARD - sincronizar Google Drive`.
2. `APP CARD - publicar web`.

## 4. Límites y evolución

El MVP depende de los límites gratuitos vigentes de Supabase y GitHub. Es adecuado para pruebas y un grupo reducido. Si aumenta el uso, se puede conservar la interfaz y migrar progresivamente a un backend propio, PostgreSQL administrado y un worker permanente.

