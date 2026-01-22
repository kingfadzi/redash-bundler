# Redash Bundler

Build self-contained Redash bundles for offline deployment on WSL/UBI9 without Docker.

## What This Does

Creates a single `.tgz` file containing:
- Redash source code (pinned version)
- Pre-built frontend assets
- Pre-built Python wheels
- Launcher scripts

The bundle can be deployed on an air-gapped system: extract, configure, run.

## Build Requirements (Build Machine)

- Alma 9 / RHEL 9 / UBI 9 (or compatible)
- Python 3.11 (or 3.10)
- Node.js 18+ and Yarn
- Poetry 1.8.x
- Git, rsync

## Quick Start

### Build

```bash
git clone https://github.com/kingfadzi/redash-bundler.git
cd redash-bundler
chmod +x build_redash_bundle.sh
./build_redash_bundle.sh
```

This produces `redash-bundle-v25.8.0.tgz`.

### Build Options

```bash
# Different Redash version
REDASH_REF=v25.1.0 ./build_redash_bundle.sh

# From a fork
REDASH_GIT_URL=https://github.com/yourfork/redash.git ./build_redash_bundle.sh

# Custom output name
OUT_TGZ=my-redash.tgz ./build_redash_bundle.sh

# Use Python 3.10 instead of 3.11
PYTHON_VERSION=python3.10 ./build_redash_bundle.sh
```

## Deploy (Target Machine)

### Prerequisites

- UBI 9 / RHEL 9 / Alma 9
- Python 3.11 (or 3.10)
- PostgreSQL (external or local)
- Redis (external or local)

```bash
# UBI 9 minimal packages
sudo dnf install -y python3.11 postgresql-libs
```

### Install

```bash
mkdir ~/redash
cd ~/redash
tar -xzf /path/to/redash-bundle-v25.8.0.tgz

cp redash.env.example redash.env
# Edit redash.env with your database/redis URLs and secrets
```

### Initialize Database (once)

```bash
./bin/init_db
```

### Run

Start each in a separate terminal (or use tmux/supervisor):

```bash
./bin/server     # Web UI on port 5000
./bin/worker     # Background job processor
./bin/scheduler  # Scheduled query runner
```

Access at: http://localhost:5000

## Configuration

Edit `redash.env`:

| Variable | Required | Description |
|----------|----------|-------------|
| `REDASH_DATABASE_URL` | Yes | PostgreSQL connection string |
| `REDASH_REDIS_URL` | Yes | Redis connection string |
| `REDASH_COOKIE_SECRET` | Yes | Random string for session cookies |
| `REDASH_SECRET_KEY` | Yes | Random string for encryption |
| `REDASH_HOST` | No | Public URL (e.g., https://redash.example.com) |
| `REDASH_LOG_LEVEL` | No | Logging level (default: INFO) |
| `REDASH_WEB_WORKERS` | No | Gunicorn workers (default: 4) |
| `REDASH_GUNICORN_TIMEOUT` | No | Request timeout in seconds (default: 60) |
| `REDASH_BIND` | No | Bind address (default: 0.0.0.0:5000) |
| `REDASH_ADDITIONAL_QUERY_RUNNERS` | No | Comma-separated list of extra data sources |

## Enabling SQL Server (Optional)

To connect to Microsoft SQL Server, install the ODBC driver on the target machine:

```bash
# Install unixODBC
sudo dnf install -y unixODBC

# Add Microsoft repository and install ODBC Driver 18
sudo curl https://packages.microsoft.com/config/rhel/9/prod.repo -o /etc/yum.repos.d/mssql-release.repo
sudo ACCEPT_EULA=Y dnf install -y msodbcsql18
```

Then add to `redash.env`:

```bash
REDASH_ADDITIONAL_QUERY_RUNNERS=redash.query_runner.mssql_odbc
```

Restart the Redash services for the changes to take effect.

## Bundle Structure

```
redash-bundle-v25.8.0.tgz
├── app/                 # Redash source + built frontend
├── wheels/              # Pre-built Python packages
├── bin/
│   ├── common.sh        # Shared utilities
│   ├── init_db          # Database initialization
│   ├── server           # Web server (gunicorn)
│   ├── worker           # RQ worker
│   └── scheduler        # RQ scheduler
├── redash.env.example   # Configuration template
└── venv/                # Created on first run
```

## License

This bundler is MIT licensed. Redash itself is BSD-2-Clause licensed.
