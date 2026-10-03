export type SendEmailMessage = {
  from: string;
  to: string;
  subject: string;
  text: string;
};

export type SendEmailEnv = {
  SEND_EMAIL: {
    send(message: SendEmailMessage): Promise<void>;
  };
};

export async function sendPlatformEmail(
  env: SendEmailEnv,
  message: SendEmailMessage,
): Promise<void> {
  await env.SEND_EMAIL.send(message);
}
