FROM node:14
# Create app directory
WORKDIR /usr/src/app

# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./

# Install app dependencies
RUN npm install

COPY . .
EXPOSE 8080
CMD [ "node", "server.js" ]