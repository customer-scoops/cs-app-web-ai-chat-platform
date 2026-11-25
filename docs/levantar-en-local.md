# Levantar Scoops XI en local con Docker

Esta guía usa el Compose de desarrollo del repositorio. Construye este fork. No uses `docker-compose.production.yaml`: esa receta descarga la imagen pública `chatwoot/chatwoot:latest` y no corre este código.

Hace falta Docker Desktop (o Docker Engine) con el comando `docker compose`.

## 1. Variables de entorno

En la raíz del repositorio:

```bash
cp .env.example .env
openssl rand -hex 64
```

Pega el resultado de `openssl` en `SECRET_KEY_BASE`. Deja el resto de estas claves así:

```bash
FRONTEND_URL=http://localhost:3000
POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DATABASE=chatwoot_dev
REDIS_PASSWORD=redis
REDIS_URL=redis://:redis@redis:6379
SMTP_ADDRESS=mailhog
SMTP_PORT=1025
RAILS_ENV=development
```

`.env` no se commitea.

Sin `POSTGRES_PASSWORD`, la imagen de Postgres no arranca. Sin `REDIS_PASSWORD`, el comando de Redis recibe un `--requirepass` vacío y también falla. `REDIS_URL` tiene que llevar la misma clave (`:redis` entre `redis://` y `@`).

## 2. Postgres en el Compose

`docker-compose.yaml` ya deja Postgres así. Si lo cambias, estos valores tienen que seguir coincidiendo con el `.env`:

```yaml
  postgres:
    image: pgvector/pgvector:pg16
    restart: always
    ports:
      - '5432:5432'
    volumes:
      - postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=chatwoot_dev
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
```

`POSTGRES_PASSWORD` y `POSTGRES_DB` tienen que coincidir con `POSTGRES_PASSWORD` y `POSTGRES_DATABASE` del `.env`. Redis ya lee `REDIS_PASSWORD` desde `.env`; no hace falta tocarlo.

## 3. Construir y levantar

Desde la raíz del repositorio:

```bash
docker compose up --build
```

La primera vez tarda: compila la imagen de Ruby, instala las gemas y corre `pnpm install` en Vite. Postgres, Redis, Mailhog, Sidekiq, Vite y Rails quedan en marcha.

Cuando el contenedor `rails` ya está arriba y el log dice que la base acepta conexiones:

```bash
docker compose exec rails bundle exec rails db:chatwoot_prepare
```

Ese comando crea el esquema y carga el seed de desarrollo. Hay que ejecutarlo una vez por base nueva. Si el contenedor `rails` todavía no existe, espera a que `docker compose up` lo deje en running y vuelve a lanzarlo.

## 4. Entrar

| Qué | Dónde |
| --- | --- |
| Aplicación | http://localhost:3000 |
| Usuario | `john@acme.inc` |
| Contraseña | `Password1!` |
| Correo de desarrollo | http://localhost:8025 |
| Vite | http://localhost:3036 |

El usuario es super admin de la instalación y administrador de la cuenta Acme Inc. El seed también crea un inbox de widget web.

## 5. Parar y volver a levantar

```bash
docker compose down
```

Los volúmenes de Postgres, Redis y dependencias se conservan. La siguiente vez basta con:

```bash
docker compose up
```

No hace falta repetir `db:chatwoot_prepare` si el volumen de Postgres sigue ahí.

Para borrar también los datos:

```bash
docker compose down -v
```

Después hay que repetir el `up` y `db:chatwoot_prepare`.

## 6. Webhooks de WhatsApp e Instagram

Meta no puede llamar a `localhost`. Un túnel rápido de Cloudflare publica el puerto 3000 con una URL `https://<aleatorio>.trycloudflare.com`. No usa el dominio `scoopsxi.com` ni pide cuenta de Cloudflare. La URL cambia cada vez que se cierra el proceso. El panel se sigue abriendo en http://localhost:3000.

Haz estos pasos con Docker ya publicando el puerto 3000.

1. En otra terminal, instala el cliente si hace falta y abre el túnel. Déjalo abierto:

```bash
brew install cloudflared
cloudflared tunnel --url http://localhost:3000
```

`cloudflared` reenvía a HTTP local. Rails no habla TLS; el certificado lo pone Cloudflare. El comando imprime `https://<aleatorio>.trycloudflare.com`. Copia esa URL, sin barra final.

2. Pégala en `.env`:

```bash
FRONTEND_URL=https://<aleatorio>.trycloudflare.com
```

3. Docker lee `.env` al crear el contenedor. Reiniciar no vuelve a cargar la variable. Recrea solo Rails:

```bash
docker compose up -d --force-recreate --no-deps rails
```

4. En desarrollo `config.hosts` ya está en `nil`, así que el host no hay que agregarlo. Chatwoot arma estas direcciones con `FRONTEND_URL`:

| Uso | Dirección |
| --- | --- |
| Webhook de WhatsApp | `https://<aleatorio>.trycloudflare.com/webhooks/whatsapp/{número del canal}` |
| Webhook de Instagram | `https://<aleatorio>.trycloudflare.com/webhooks/instagram` |
| Redirección de Instagram | `https://<aleatorio>.trycloudflare.com/instagram/callback` |

5. En la configuración del canal de WhatsApp, reintenta el webhook. Meta hace el GET y Rails devuelve el challenge si el `webhook_verify_token` del canal coincide. En la app de Meta, pega la redirección y el webhook de Instagram de la tabla y vuelve a verificarlos.

6. Una petición de WhatsApp sin token debe responder 401:

```bash
curl -i "https://<aleatorio>.trycloudflare.com/webhooks/whatsapp/+51900000000?hub.mode=subscribe&hub.verify_token=incorrecto&hub.challenge=123"
```

Sustituye el número por el del canal.

Si cierras `cloudflared`, la URL cambia. Repite desde el paso 1: nuevo `FRONTEND_URL`, recrea `rails` y vuelve a pegar las tres direcciones en Meta.

El panel se usa en http://localhost:3000. La URL de Cloudflare es para Meta. Si abres el dashboard por el túnel, Vite pide miles de archivos de idioma y Cloudflare los corta.

## Puertos que ocupa

`3000` (Rails), `3036` (Vite), `5432` (Postgres), `6379` (Redis), `1025` y `8025` (Mailhog). Si alguno ya está en uso en la máquina, el contenedor correspondiente no arranca.
