FROM squidfunk/mkdocs-material:latest AS build
WORKDIR /docs
COPY . .
RUN mkdocs build

FROM nginx:alpine
COPY --from=build /docs/site /usr/share/nginx/html
EXPOSE 80
