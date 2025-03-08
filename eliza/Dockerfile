FROM node:22-slim

# Set working directory
WORKDIR /app

# Install pnpm
RUN npm install -g pnpm@9.14.2

# Copy package.json and related files
COPY package.json pnpm-lock.yaml* ./

# Install dependencies
RUN pnpm install

# Copy the rest of the application
COPY . .

# Build the application
RUN pnpm run build

# Expose any necessary ports (add specific ports if needed)
# EXPOSE 8080

# Start the application
CMD ["pnpm", "start"]
