/**
 * Basic route handler for callback url
 * @param request
 * @returns
 */

export async function GET(request: Request) {
  console.log("GET request received:", request);
  return new Response();
}

export async function POST(request: Request) {
  console.log("POST request received:", request);
  const body = await request.json();
  console.log("POST body:", body);
  return new Response();
}
