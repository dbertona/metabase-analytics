FROM apache/superset:6.1.0

USER root
# La imagen 6.x usa venv en /app/.venv (pip del sistema no basta)
RUN uv pip install --python /app/.venv/bin/python --no-cache psycopg2-binary
USER superset
