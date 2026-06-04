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
    console.error('[FATAL] Missing custom SMTP configurations in production environment. Dynamic Ethereal mail is disabled for security.');
    // In production with missing SMTP, use a silent secure mock transporter to prevent OTP leaks
    transporter = {
      sendMail: async (mailOptions: any) => {
        console.warn(`[SECURITY WARNING] Attempted to send email to ${mailOptions.to.replace(/(?<=.{2}).(?=[^@]*?@)/g, '*')} but SMTP is unconfigured in production.`);
        console.log(`[DEVELOPER MOCK LOG] Verification email content for ${mailOptions.to}:\nSubject: ${mailOptions.subject}\nBody: ${mailOptions.text}\n`);
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
  try {
    const transport = await getTransporter();
    const isProduction = (process.env.NODE_ENV || 'development') === 'production';
    
    // Print verification/security codes to console immediately for convenience during development/testing
    if (!isProduction) {
      console.log('\n--- [OUTGOING SECURITY EMAIL] ---');
      console.log(`To: ${to}`);
      console.log(`Subject: ${subject}`);
      console.log(`Body: ${text}`);
      console.log('---------------------------------\n');
    } else {
      // Mask email for production logs to protect user PII
      const maskedEmail = to.replace(/(?<=.{2}).(?=[^@]*?@)/g, '*');
      console.log(`[AUDIT] Dispatching security email to: ${maskedEmail}`);
    }

    // Run the actual sendMail and await its completion to avoid silently failing background tasks
    const info = await transport.sendMail({
      from: '"Chatly Security" <security@chatly.secure>',
      to,
      subject,
      text,
      html
    });

    console.log(`Email dispatched successfully to ${to}. Message ID: ${info.messageId}`);
    
    if (!isProduction) {
      const previewUrl = nodemailer.getTestMessageUrl(info);
      if (previewUrl) {
        console.log(`\n📬 [TESTING MODE] Read your verification code at Ethereal URL: ${previewUrl}\n`);
      }
    }

    return true;
  } catch (err: any) {
    console.error('Failed to send email:', err.message);
    return false;
  }
}

