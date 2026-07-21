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

## FASE 4 — Flujo de promoción, producción y entrega

### 4.1 Concepto clave: qué viaja y qué NO viaja entre ambientes

| Elemento | Cómo se mueve | Medio |
|---|---|---|
| Código (módulos, temas, composer) | Automático | Git → push → autodeploy |
| **Configuración** (content types, vistas, campos, permisos) | **Manual: exportar/importar** | `drush cex` → Git → `drush cim` |
| Contenido (nodos, usuarios, medios) | NO se mueve solo | Copia de BD, solo si se pide |
| Archivos subidos | NO se mueve solo | Volumen por ambiente |

> ESTO ES LO MÁS IMPORTANTE DEL FLUJO.
> Si un dev crea un content type en DEV desde la interfaz, ese cambio queda en la
> BASE DE DATOS de DEV. Hacer merge a `qa` NO lo lleva. Hay que exportarlo a
> `config/sync` y commitearlo. Sin ese paso, la promoción mueve código vacío.

### 4.2 Ciclo de trabajo del desarrollador (día a día)

Trabajo local, con el compose local:
```bash
cd ~/Projects/ulatina && git checkout develop && git pull origin develop
docker compose up -d
```

Tras hacer cambios de configuración en la interfaz de Drupal:
```bash
docker compose exec drupal vendor/bin/drush cex -y
```
> Exporta la configuración de la BD a archivos YAML en `config/sync`.
> Sin este comando, el cambio no sale nunca del computador del dev.

```bash
git add config/sync && git commit -m "config: nuevo content type Noticias"
git push origin develop
```
> El push dispara el autodeploy en DEV.

### 4.3 Promoción DEV → QA

```bash
git checkout qa && git pull origin qa
git merge develop
git push origin qa
```
> Dispara el autodeploy del ambiente QA.

Después del deploy, aplicar la configuración en QA
(terminal del contenedor `drupal` de QA en Dokploy):
```bash
cd /var/www/html && vendor/bin/drush cim -y && vendor/bin/drush cr
```
> `cim` importa los YAML a la BD de QA. `cr` limpia caché.
> SIN ESTE PASO el sitio QA sigue con la configuración vieja.

Verificar que no quedaron diferencias:
```bash
vendor/bin/drush config:status
```
> Debe decir que no hay cambios pendientes.

### 4.4 Promoción QA → PRODUCCIÓN

```bash
git checkout main && git pull origin main
git merge qa
git tag -a v1.0.0 -m "Primera entrega a produccion"
git push origin main --tags
```
> El tag permite volver a una versión exacta si algo sale mal.

Secuencia segura en producción (terminal del contenedor):
```bash
cd /var/www/html && vendor/bin/drush sql:dump --gzip --result-file=/tmp/backup-pre-deploy.sql
```
> SIEMPRE respaldar antes de tocar producción.

```bash
vendor/bin/drush updatedb -y && vendor/bin/drush cim -y && vendor/bin/drush cr
```
> `updatedb` aplica actualizaciones de esquema de módulos, `cim` la configuración.
> Este es el orden correcto: base de datos primero, configuración después.

### 4.5 Regla de oro de ramas

```
develop ──merge──> qa ──merge──> main
  (DEV)            (QA)         (PROD)
```
- El código SOLO fluye hacia adelante. Nunca se hace merge de `qa` a `develop`.
- Si hay un bug urgente en producción: rama desde `main`, arreglo, merge a `main`,
  y luego ese mismo merge se baja a `qa` y `develop` para no perder el arreglo.
- Nadie hace push directo a `main`.

### 4.6 Crear el ambiente de PRODUCCIÓN (cuando llegue el dominio real)

Mismos pasos de la Fase 3, cambiando:

| Campo | Valor |
|---|---|
| Environment | `production` |
| Name / App Name | `drupal-prod` / `ulatina-drupal-prod` |
| Branch | `main` |
| DB_NAME / DB_USER | `ulatina_prod` |
| Secretos | generar nuevos, distintos de DEV y QA |
| Autodeploy | APAGADO (producción se despliega a mano) |

Con dominio real sí se activa HTTPS:
Domains → Host `www.dominiodelcliente.com` → HTTPS ON → Certificado Let's Encrypt.
> Requiere que el DNS (registro A) apunte a `82.25.84.215` ANTES de pedir el certificado.

Endurecer `settings.php` para producción (restringir los hosts permitidos):
```php
$settings['trusted_host_patterns'] = ['^www\.dominiodelcliente\.com$'];
```
> Hoy está en `.*` para permitir los dominios temporales sslip.io.

### 4.7 Respaldos

Base de datos, bajo demanda (terminal del contenedor):
```bash
cd /var/www/html && vendor/bin/drush sql:dump --gzip --result-file=/tmp/backup.sql
```

Automáticos desde Dokploy:
- Pestaña **Backups**: respaldo programado de la base de datos.
- Pestaña **Volume Backups**: respaldo del volumen de archivos subidos.
> Ambos se configuran por ambiente. Producción debe tener los dos activos.

### 4.8 Accesos a entregar a los desarrolladores

| Recurso | Valor |
|---|---|
| Repositorio | `github.com/jrozowdark/ulatina` |
| Rama de trabajo | `develop` |
| Sitio DEV | `http://ulatina-dev-82-25-84-215.sslip.io` |
| Sitio QA | `http://ulatina-qa-82-25-84-215.sslip.io` |
| Panel Dokploy | `http://82.25.84.215:3000` |
| Usuario admin Drupal | `jrosas` |

Levantar el proyecto en local por primera vez:
```bash
git clone git@github.com:jrozowdark/ulatina.git && cd ulatina
cp .env.example .env
openssl rand -hex 32
docker compose up -d --build
docker compose exec drupal vendor/bin/drush site:install standard -y
```
> Cada dev genera su propio `.env` local. Ese archivo nunca se sube al repo.

### 4.9 Errores conocidos y su causa

**MariaDB da "Access denied" para root y para el usuario**
> El volumen se inicializó con credenciales distintas a las actuales. MariaDB solo
> crea usuarios en el PRIMER arranque del volumen. Solución: borrar el servicio con
> sus volúmenes y recrearlo, poniendo las variables ANTES del primer Deploy.

**El sitio responde 500 y el contenedor queda `unhealthy`**
> Drupal conecta a la BD pero no encuentra tablas. Falta correr `drush site:install`.

**El dominio da 404**
> Dos causas: el contenedor no está `healthy` (Traefik omite crear la ruta), o falta
> hacer Deploy después de agregar el dominio. En Compose las labels de Traefik solo
> se leen en un despliegue nuevo.

**Un cambio de configuración no aparece en QA**
> Falta `drush cex` en origen, o falta `drush cim` en destino. Ver sección 4.1.
