"""API minimale : elle sert de prétexte à l'exploitation (bases, métriques, logs)."""

import logging
import os
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Dict

import psycopg2
from fastapi import FastAPI, Query, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)
from psycopg2.extras import RealDictCursor
from pydantic import BaseModel, Field
from pymongo import DESCENDING, MongoClient
from pymongo.errors import PyMongoError


# ---------------------------------------------------------------------------
# Configuration des logs
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

log = logging.getLogger("api")


# ---------------------------------------------------------------------------
# Application FastAPI
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Production-Ready Stack API",
    version="1.0.0",
)


# ---------------------------------------------------------------------------
# Métriques Prometheus
# ---------------------------------------------------------------------------

REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests",
    ["method", "path", "status"],
)

LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP latency",
    ["method", "path"],
)


# ---------------------------------------------------------------------------
# Connexion PostgreSQL
# ---------------------------------------------------------------------------

def pg_connect():
    return psycopg2.connect(
        host=os.environ["POSTGRES_HOST"],
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["APP_DB_USER"],
        password=os.environ["APP_DB_PASSWORD"],
        connect_timeout=3,
    )


@contextmanager
def pg_cursor():
    conn = pg_connect()

    try:
        with conn:  # commit ou rollback automatique
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                yield cur
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Connexion MongoDB
# ---------------------------------------------------------------------------

mongo_client = MongoClient(
    host=os.environ["MONGO_HOST"],
    port=27017,
    username=os.environ["MONGO_APP_USER"],
    password=os.environ["MONGO_APP_PASSWORD"],
    authSource=os.environ["MONGO_APP_DB"],
    serverSelectionTimeoutMS=2000,
)

events_col = mongo_client[
    os.environ["MONGO_APP_DB"]
]["events"]


# ---------------------------------------------------------------------------
# Métriques Prometheus + gestion des erreurs
# ---------------------------------------------------------------------------

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    status = 500

    try:
        response = await call_next(request)
        status = response.status_code
        return response

    finally:
        route = request.scope.get("route")
        path = route.path if route else "unmatched"

        REQUESTS.labels(
            request.method,
            path,
            str(status),
        ).inc()

        LATENCY.labels(
            request.method,
            path,
        ).observe(time.perf_counter() - start)


@app.exception_handler(psycopg2.OperationalError)
async def postgres_down_handler(
    request: Request,
    exc: psycopg2.OperationalError,
):
    log.error(
        "PostgreSQL indisponible: %s",
        str(exc).strip(),
    )

    return JSONResponse(
        status_code=503,
        content={"detail": "PostgreSQL indisponible"},
    )


@app.exception_handler(PyMongoError)
async def mongo_down_handler(
    request: Request,
    exc: PyMongoError,
):
    log.error(
        "MongoDB indisponible: %s",
        str(exc).strip(),
    )

    return JSONResponse(
        status_code=503,
        content={"detail": "MongoDB indisponible"},
    )


# ---------------------------------------------------------------------------
# Modèles Pydantic
# ---------------------------------------------------------------------------

class UserIn(BaseModel):
    name: str = Field(
        min_length=1,
        max_length=100,
    )

    email: str = Field(
        min_length=3,
        max_length=200,
    )


class EventIn(BaseModel):
    type: str = Field(
        min_length=1,
        max_length=50,
    )

    payload: Dict[str, Any] = {}


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    """
    Liveness : le processus répond.
    Utilisé par le healthcheck Docker.
    """
    return {"status": "ok"}


@app.get("/ready")
def ready():
    """
    Readiness : les dépendances répondent-elles ?
    """

    checks = {}

    # Vérification PostgreSQL
    try:
        with pg_cursor() as cur:
            cur.execute("SELECT 1")

        checks["postgres"] = "ok"

    except Exception as exc:  # noqa: BLE001
        log.error("readiness postgres: %s", exc)
        checks["postgres"] = "down"

    # Vérification MongoDB
    try:
        mongo_client.admin.command("ping")
        checks["mongo"] = "ok"

    except Exception as exc:  # noqa: BLE001
        log.error("readiness mongo: %s", exc)
        checks["mongo"] = "down"

    healthy = all(
        value == "ok"
        for value in checks.values()
    )

    return JSONResponse(
        status_code=200 if healthy else 503,
        content=checks,
    )


@app.post("/users", status_code=201)
def create_user(user: UserIn):
    with pg_cursor() as cur:
        cur.execute(
            """
            INSERT INTO users (name, email)
            VALUES (%s, %s)
            RETURNING id, name, email, created_at
            """,
            (user.name, user.email),
        )

        return cur.fetchone()


@app.get("/users")
def list_users(
    limit: int = Query(
        20,
        ge=1,
        le=100,
    ),
):
    with pg_cursor() as cur:
        cur.execute(
            """
            SELECT id, name, email, created_at
            FROM users
            ORDER BY id DESC
            LIMIT %s
            """,
            (limit,),
        )

        return cur.fetchall()


@app.get("/users/search")
def search_user(email: str):
    """
    Requête volontairement non indexée au départ.
    Utilisée pour l'exercice EXPLAIN ANALYZE.
    """

    with pg_cursor() as cur:
        cur.execute(
            """
            SELECT id, name, email
            FROM users
            WHERE email = %s
            """,
            (email,),
        )

        return cur.fetchall()


@app.post("/events", status_code=201)
def create_event(event: EventIn):
    doc = {
        "type": event.type,
        "payload": event.payload,
        "created_at": datetime.now(timezone.utc),
    }

    result = events_col.insert_one(doc)

    return {
        "id": str(result.inserted_id),
        "type": event.type,
    }


@app.get("/events")
def list_events(
    limit: int = Query(
        20,
        ge=1,
        le=100,
    ),
):
    docs = (
        events_col
        .find({}, {"_id": 0})
        .sort("created_at", DESCENDING)
        .limit(limit)
    )

    return list(docs)


@app.get(
    "/metrics",
    include_in_schema=False,
)
def metrics():
    return Response(
        generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )
