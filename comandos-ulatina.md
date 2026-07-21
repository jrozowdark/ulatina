# Comandos · Proyecto ULatina (Drupal 11 + Dokploy)

> Documento vivo. Se va alimentando fase por fase. Comando + para qué sirve.
> Equipo: MacBook Air M4 · OrbStack · `docker compose` (plugin, sin guion).

---

## FASE 1 — Scaffold local y validación en OrbStack

### 1. Descomprimir el paquete en la carpeta del proyecto
```bash
mkdir -p ~/Projects/ulatina && cd ~/Projects/ulatina
unzip ~/Downloads/ulatina-fase1.zip -d .
```
> Deja todos los archivos base (Dockerfile, compose, composer.json, etc.).

### 2. Crear el archivo de entorno real
```bash
cp .env.example .env
```
> `.env` guarda credenciales reales. NUNCA se sube al repo (ya está en `.gitignore`).

### 3. Generar el hash de seguridad de Drupal
```bash
openssl rand -hex 32
```
> Copia el resultado en `DRUPAL_HASH_SALT` dentro de `.env`.
> Cambia también `DB_PASSWORD` y `DB_ROOT_PASSWORD` (solo alfanumérico + `_`).

### 4. Levantar el stack (primer build baja Drupal core vía Composer)
```bash
docker compose up -d --build
```
> Construye la imagen, baja Drupal 11 y arranca Drupal + MariaDB.
> El primer build tarda (descarga core). Ver progreso: `docker compose logs -f drupal`

### 5. Extraer el composer.lock generado y dejarlo versionado
```bash
docker compose cp drupal:/var/www/html/composer.lock ./composer.lock
```
> Fija versiones exactas → builds reproducibles en dev y QA. Se commitea al repo.

### 6. Instalar Drupal por CLI (drush)
```bash
docker compose exec drupal vendor/bin/drush site:install standard \
  --account-name=jrosas \
  --account-pass=CambiaEstaClave \
  --site-name="ULatina" -y
```
> Instala Drupal usando la BD del `.env`. Usuario admin: `jrosas`.

### 7. Validar en el navegador
```bash
open http://localhost:8080
```
> Debe cargar el sitio Drupal 11. Login admin en `http://localhost:8080/user/login`.

### Comandos útiles de operación (local)
```bash
docker compose ps                      # estado de contenedores
docker compose logs -f drupal          # logs del web
docker compose exec drupal bash        # entrar al contenedor
docker compose exec drupal vendor/bin/drush cr   # limpiar caché de Drupal
docker compose down                    # apagar (mantiene volúmenes/datos)
docker compose down -v                 # apagar y BORRAR datos (¡cuidado!)
```

---

### Solución de problemas encontrados en Fase 1

**Error `curl error 28 ... Connection timed out` durante el build**
> Composer no alcanza GitHub por intentar IPv6. Ya resuelto en el Dockerfile con:
> `RUN echo 'precedence ::ffff:0:0/96 100' >> /etc/gai.conf`

**Error `contains a Composer plugin which is blocked by your allow-plugins`**
> Falta autorizar el plugin. Se agrega a `config.allow-plugins` en `composer.json`.

**Error `Drush was unable to drop all tables because mysql was not found`**
> Pasa si ya instalaste Drupal por el navegador. Vacía la BD y reinstala por Drush:
```bash
docker compose exec mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`ulatina\`; CREATE DATABASE \`ulatina\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; GRANT ALL ON \`ulatina\`.* TO \`ulatina\`@\`%\`;"'
```

---

## FASE 2 — Repo GitHub y ramas

### Contexto
Repo destino: `git@github.com:jrozowdark/ulatina.git` (vacío).
Estrategia de ramas: `main` (estable) → `develop` (ambiente DEV) → `qa` (ambiente QA).

### 1. Verificar que el composer.lock existe (CRÍTICO)
```bash
cd ~/Projects/ulatina && ls -lh composer.lock
```
> Si NO aparece, extráelo del contenedor:
> `docker compose cp drupal:/var/www/html/composer.lock ./composer.lock`
> Sin este archivo, dev y QA podrían construirse con versiones distintas de Drupal.

### 2. Inicializar el repo y confirmar que el .env queda ignorado
```bash
git init -b main
git status --short | grep "^?? .env$" && echo "PELIGRO: .env NO ignorado" || echo "OK: .env ignorado"
```
> `git init -b main` inicializa el repo con la rama principal llamada `main`.
> El `.env` tiene credenciales reales: jamás debe llegar a GitHub.

### 3. Primer commit
```bash
git add .
git commit -m "Fase 1: scaffold Drupal 11 + Docker + MariaDB"
```

### 4. Conectar el repo remoto y subir main
```bash
git remote add origin git@github.com:jrozowdark/ulatina.git
git push -u origin main
```
> Si falla la autenticación, tu Mac no tiene llave SSH registrada. Ver paso 4b.

### 4b. (Solo si falla) Generar y registrar llave SSH
```bash
ssh-keygen -t ed25519 -C "jrosas@denicolas.co" -f ~/.ssh/id_ed25519_github
pbcopy < ~/.ssh/id_ed25519_github.pub
```
> Genera la llave y copia la pública al portapapeles.
> Pégala en GitHub → Settings → SSH and GPG keys → New SSH key.
> Luego registra la llave en el agente y prueba:
```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_github
ssh -T git@github.com
```
> Debe responder "Hi jrozowdark! You've successfully authenticated".

### 5. Crear las ramas de ambientes
```bash
git branch develop
git branch qa
git push origin develop qa
```
> `develop` alimenta el ambiente DEV y `qa` el ambiente QA en Dokploy.
> Ambas nacen del mismo commit, así que los dos ambientes arrancan idénticos.

### 6. Verificar que todo subió
```bash
git ls-remote --heads origin
```
> Debe listar las tres ramas remotas: `main`, `develop`, `qa`.

### Flujo de trabajo para los desarrolladores
```bash
git checkout develop
git add . && git commit -m "descripcion del cambio"
git push origin develop
```
> Trabajar siempre desde `develop`. El push dispara el auto-deploy en DEV.

```bash
git checkout qa && git merge develop && git push origin qa
```
> Promueve a QA cuando el cambio ya fue validado en DEV.

---

## FASE 3 — Dokploy: GitHub App + environments + Compose

### Arquitectura
```
Dokploy (82.25.84.215:3000) · Proyecto "Ulatina"
  ├── Environment "development" → Compose "drupal-dev" → rama develop
  └── Environment "qa"          → Compose "drupal-qa"  → rama qa
```
Cada ambiente tiene su propia BD y sus propios volúmenes: son independientes.

### Por qué un compose separado para Dokploy
| Archivo | Uso | Puertos |
|---|---|---|
| `docker-compose.yml` | Local (OrbStack) | Bindea `8080:80` |
| `docker-compose.dokploy.yml` | Servidor Dokploy | Sin bind; enruta Traefik |

En Dokploy NO se bindean puertos: los reserva Traefik. Además, si dev y QA
bindearan el mismo puerto, el segundo despliegue fallaría.
La BD queda en una red `interna` privada por stack, así el Drupal de DEV
no puede alcanzar la base de datos de QA.

### 1. Subir el compose de Dokploy a las tres ramas
```bash
cd ~/Projects/ulatina
git checkout main
git add docker-compose.dokploy.yml comandos-ulatina.md Dockerfile
git commit -m "Fase 3: compose para Dokploy + mariadb-client"
git push origin main
```
> Sube el archivo a la rama estable primero.

```bash
git checkout develop && git merge main && git push origin develop
git checkout qa && git merge main && git push origin qa
git checkout develop
```
> Propaga el mismo commit a los dos ambientes y te deja parado en `develop`.

### 2. Generar los secretos de cada ambiente
```bash
echo "DEV  HASH_SALT: $(openssl rand -hex 32)"
echo "DEV  DB_PASS:   $(openssl rand -hex 16)"
echo "DEV  DB_ROOT:   $(openssl rand -hex 16)"
echo "QA   HASH_SALT: $(openssl rand -hex 32)"
echo "QA   DB_PASS:   $(openssl rand -hex 16)"
echo "QA   DB_ROOT:   $(openssl rand -hex 16)"
```
> `openssl rand -hex` genera solo caracteres 0-9a-f: sin símbolos `$` que rompan
> la interpolación de Docker Compose. Guárdalos: se pegan en Dokploy.

### 3. Conectar GitHub a Dokploy (una sola vez)
En Dokploy: **Settings → Git → GitHub → Create GitHub App**
1. Nombra la app (ej. `dokploy-webdigitalark`) y autoriza en GitHub.
2. En GitHub, al instalar la app elige **Only select repositories** → `jrozowdark/ulatina`.
3. Vuelve a Dokploy y confirma que el repo aparece en la lista.

> Se usa GitHub App y no llave SSH porque la App instala el webhook
> automáticamente: eso es lo que habilita el auto-deploy de la Fase 4.

### 4. Crear el ambiente DEV
En el proyecto **Ulatina** → pestaña de environments → **Create Environment** → `development`.
Dentro de ese environment: **Create Service → Compose**.

| Campo | Valor |
|---|---|
| Name | `drupal-dev` |
| Provider | GitHub |
| Repository | `jrozowdark/ulatina` |
| Branch | `develop` |
| Compose Path | `./docker-compose.dokploy.yml` |
| Compose Type | **Docker Compose** (NO Stack) |

> Debe ser "Docker Compose": en modo Stack (Swarm) la directiva `build` no funciona.

### 5. Variables de entorno de DEV
En el servicio `drupal-dev` → pestaña **Environment**, pega:
```
DB_HOST=mariadb
DB_PORT=3306
DB_NAME=ulatina_dev
DB_USER=ulatina_dev
DB_PASSWORD=<DEV DB_PASS del paso 2>
DB_ROOT_PASSWORD=<DEV DB_ROOT del paso 2>
DRUPAL_HASH_SALT=<DEV HASH_SALT del paso 2>
```

### 6. Desplegar DEV
Botón **Deploy**. El primer build tarda varios minutos (baja Drupal core).
Sigue el avance en la pestaña **Logs** o **Deployments**.

### 7. Asignar el dominio temporal
Servicio `drupal-dev` → pestaña **Domains** → **Add Domain**:

| Campo | Valor |
|---|---|
| Service Name | `drupal` |
| Container Port | `80` |
| Host | usar el botón de dominio generado (`*.traefik.me`) |
| HTTPS | activado |

> IMPORTANTE: si el healthcheck del contenedor no pasa, Traefik omite crear la ruta
> y el dominio dará 404. Verifica primero que el servicio esté `healthy`.

### 8. Instalar Drupal en DEV
En el servicio → pestaña **Terminal** (o **Advanced → Terminal**), sobre el contenedor `drupal`:
```bash
vendor/bin/drush site:install standard \
  --account-name=jrosas --account-pass=CambiaEstaClave \
  --site-name="ULatina DEV" -y
```
> Instala Drupal usando las variables de entorno del ambiente.

```bash
vendor/bin/drush status
```
> Debe decir `Database: Connected` y `Drupal bootstrap: Successful`.

### 9. Repetir para QA
Mismos pasos 4 a 8, cambiando:

| Campo | Valor QA |
|---|---|
| Environment | `qa` |
| Name | `drupal-qa` |
| Branch | `qa` |
| DB_NAME / DB_USER | `ulatina_qa` |
| Secretos | los de QA del paso 2 |
| Site name | `ULatina QA` |

### 10. (Recomendado) Activar aislamiento de despliegues
En Dokploy: **Settings → Isolated Deployments → activar**.
> Da a cada proyecto su propia red. Evita que servicios con el mismo nombre
> en distintos ambientes se vean entre sí.

---

## FASE 4 — Auto-deploy + dominios definitivos (pendiente)
