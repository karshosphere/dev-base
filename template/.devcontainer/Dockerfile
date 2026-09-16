FROM dev-base:latest

USER root
RUN apk add --no-cache \
        nodejs \
        npm \
        python3 \
        uv
USER dev

ENV UV_PROJECT_ENVIRONMENT=/home/dev/.venv
ENV PATH=/home/dev/.venv/bin:$PATH
COPY --chown=dev pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

CMD ["bash"]
