FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
# daemon off keeps nginx in the foreground so the container stays up
CMD ["nginx", "-g", "daemon off;"]
