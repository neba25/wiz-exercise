FROM node:20-slim

WORKDIR /usr/src/app

COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./
COPY public ./public

# Required by the exercise: a file named wizexercise.txt containing your name
# Replace "YOUR NAME HERE" or pass --build-arg NAME="Jane Doe" at build time.
ARG NAME="YOUR NAME HERE"
RUN echo "$NAME" > /wizexercise.txt

EXPOSE 3000
CMD ["node", "server.js"]
