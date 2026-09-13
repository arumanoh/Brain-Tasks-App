# Brain Tasks App - Production Dockerfile
# This repo ships only the pre-built Vite/React output (dist/), so we skip
# the build stage entirely and just serve the static files with nginx.

FROM nginx:1.27-alpine

# Remove default nginx static content and default server config
RUN rm -rf /usr/share/nginx/html/* \
    && rm -f /etc/nginx/conf.d/default.conf

# Custom server block: listens on 3000, SPA-friendly routing fallback
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy the production build
COPY dist/ /usr/share/nginx/html/

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
