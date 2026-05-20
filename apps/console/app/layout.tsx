import type { Metadata } from 'next';
import Script from 'next/script';
import '@xterm/xterm/css/xterm.css';
import './globals.css';

export const metadata: Metadata = {
  title: 'Mira Console',
  description: 'Remote device terminal workbench',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>
        <Script src="/vendor/h264decoder.js" strategy="beforeInteractive" />
        {children}
      </body>
    </html>
  );
}
