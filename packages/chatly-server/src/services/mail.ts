import nodemailer from 'nodemailer';

let transporter: nodemailer.Transporter | null = null;

async function getTransporter(): Promise<nodemailer.Transporter> {
  if (transporter) return transporter;

  const host = process.env.SMTP_HOST;
  const port = parseInt(process.env.SMTP_PORT || '587', 10);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  const isProduction = (process.env.NODE_ENV || 'development') === 'production';

  if (host && user && pass) {
    console.log('Using configured custom SMTP server:', host);
    transporter = nodemailer.createTransport({
      host,
      port,
      secure: port === 465,
      auth: { user, pass }
    });
  } else if (isProduction) {
    console.warn('[SECURITY WARNING] SMTP is not configured. Set SMTP_HOST, SMTP_USER, SMTP_PASS env vars. Falling back to local console mock to prevent registration failure.');
    transporter = {
      sendMail: async (mailOptions: any) => {
        const maskedEmail = mailOptions.to.replace(/(?<=.{2}).(?=[^@]*?@)/g, '*');
        console.warn(`[SECURITY WARNING] SMTP unconfigured. Email to ${maskedEmail} simulated.`);
        return { messageId: 'unconfigured-smtp-production-id' };
      }
    } as any;
  } else {
    console.log('No SMTP configurations found. Initializing a free dynamic Ethereal test account...');
    try {
      const testAccount = await nodemailer.createTestAccount();
      console.log('Ethereal Mail account registered: ', testAccount.user);
      transporter = nodemailer.createTransport({
        host: testAccount.smtp.host,
        port: testAccount.smtp.port,
        secure: testAccount.smtp.secure,
        auth: {
          user: testAccount.user,
          pass: testAccount.pass
        }
      });
    } catch (err: any) {
      console.error('Failed to register Ethereal Mail test credentials. Emulating transporter via console output: ', err.message);
      // Fallback transporter printing directly to stdout
      transporter = {
        sendMail: async (mailOptions: any) => {
          console.log('\n--- [EMULATED MAIL SERVICE] ---');
          console.log(`To: ${mailOptions.to}`);
          console.log(`Subject: ${mailOptions.subject}`);
          console.log(`Body: ${mailOptions.text}`);
          console.log('-------------------------------\n');
          return { messageId: 'mocked-console-message-id' };
        }
      } as any;
    }
  }

  return transporter!;
}

export async function sendEmail({ to, subject, text, html }: { to: string; subject: string; text: string; html?: string }) {
  const isProduction = (process.env.NODE_ENV || 'development') === 'production';

  try {
    const transport = await getTransporter();

    // In production: mask email in logs, NEVER log message body (contains OTPs)
    if (isProduction) {
      const maskedEmail = to.replace(/(?<=.{2}).(?=[^@]*?@)/g, '*');
      console.log(`[AUDIT] Dispatching security email to: ${maskedEmail}`);
    } else {
      // Development only: print OTP to console so devs can test without real SMTP
      console.log('\n--- [DEV OUTGOING EMAIL] ---');
      console.log(`To: ${to}`);
      console.log(`Subject: ${subject}`);
      console.log(`Body: ${text}`);
      console.log('----------------------------\n');
    }

    const info = await transport.sendMail({
      from: '"Chatly" <security@chatly.app>',
      to,
      subject,
      text,
      html,
    });

    if (!isProduction) {
      const previewUrl = nodemailer.getTestMessageUrl(info);
      if (previewUrl) {
        console.log(`📬 Preview at: ${previewUrl}\n`);
      }
    }

    return true;
  } catch (err: any) {
    console.error('Failed to send email:', err.message);
    return false;
  }
}

