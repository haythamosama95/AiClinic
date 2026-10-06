export default {
  async fetch(): Promise<Response> {
    return new Response("not found", { status: 404 });
  },
  async scheduled(): Promise<void> {},
};
