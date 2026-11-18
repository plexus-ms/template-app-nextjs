import { connection } from 'next/server';

// For the compose healthcheck (docker/compose.yaml); the proxy refuses the path from outside. An app that cannot serve without its dependencies checks them here.
export async function GET() {
  await connection();
  return new Response(null);
}
