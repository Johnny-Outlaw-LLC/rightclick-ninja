import type { Metadata } from "next";
import { Anybody, Figtree } from "next/font/google";
import "./globals.css";

const display = Anybody({
  subsets: ["latin"],
  variable: "--font-display",
  weight: ["500", "700", "800"],
});

const body = Figtree({
  subsets: ["latin"],
  variable: "--font-body",
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  title: "Right Click Ninja",
  description:
    "Change file dates or take screenshots directly from Finder's right-click menu.",
  metadataBase: new URL("https://rightclick.ninja"),
  openGraph: {
    title: "Right Click Ninja",
    description:
      "Change file dates or take screenshots directly from Finder's right-click menu.",
    url: "https://rightclick.ninja",
    siteName: "Right Click Ninja",
    type: "website",
  },
  icons: { icon: "/favicon.ico" },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  );
}
