FROM node:20-alpine AS ui-builder

RUN mkdir /app \
    && corepack enable \
    && corepack prepare pnpm@8.15.4 --activate

WORKDIR /app

COPY package.json pnpm-lock.yaml /app/

RUN apk add --update --no-cache g++ make git \
    && pnpm install \
    && apk del g++ make

COPY . /app

RUN pnpm run build

FROM nginx:1.25-alpine
COPY --from=ui-builder /app/dist /usr/share/nginx/html
COPY --from=ui-builder /app/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
# CMD ["nginx"]
