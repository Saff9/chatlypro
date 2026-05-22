import "@/styles/globals.css";
import Navbar from "@/components/navbar";
import ScrollTop from "@/components/scroll-top";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "GenZ Owais",
  description: "Modern web developer portfolio of GenZ Owais",
  openGraph: {
    title: "GenZ Owais",
    description: "Fast, modern web experiences",
    url: "https://genzowais.com",
    siteName: "GenZ Owais",
    images: [{ url: "/icon.png", width: 512, height: 512 }],
    locale: "en_US",
    type: "website"
  },
  twitter: {
    card: "summary_large_image",
    title: "GenZ Owais",
    description: "Fast, modern web experiences",
    images: ["/icon.png"]
  }
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Navbar />
        {children}
        <ScrollTop />
      </body>
    </html>
  );
}
