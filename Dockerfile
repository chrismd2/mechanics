# Development Dockerfile for Phoenix/Elixir application (mechanics)
FROM elixir:1.17.2-otp-27
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs
RUN npm install -g yarn

WORKDIR /app
COPY . /app/

ARG DATABASE_URL
ARG PHX_HOST
ENV DATABASE_URL=$DATABASE_URL
ENV PHX_HOST=$PHX_HOST
ENV MIX_ENV=dev

RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get
RUN mix deps.compile

RUN mix tailwind.install --if-missing
WORKDIR /app/assets
RUN if [ ! -f tailwind.config.js ]; then \
      printf '%s\n' \
        'module.exports = {' \
        '  content: ["./js/**/*.js", "../lib/mechanics_web.ex", "../lib/mechanics_web/**/*.*ex"],' \
        '  theme: { extend: {} },' \
        '  plugins: []' \
        '};' > tailwind.config.js; \
    fi
RUN if [ -f package.json ]; then npm ci || npm install; fi
WORKDIR /app

RUN mix assets.deploy
RUN mix compile

EXPOSE 80
EXPOSE 443
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:4000/ || exit 1
