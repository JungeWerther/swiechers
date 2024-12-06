import MainLayout from "@/components/MainLayout";
import type { Metadata } from "next";
import { DM_Mono } from "next/font/google";
import "./globals.css";

const font = DM_Mono({
  subsets: ["latin"],
  weight: "400",
});

export const metadata: Metadata = {
  title: "Seb Wiechers",
  description: "Data Wizard, Software Engineer, Entrepreneur",
  twitter: {
    site: "@site",
    card: "summary_large_image",
    images: "https://swiechers.nl/og_image.JPG",
    creator: "@creator",
    title: "Seb Wiechers",
    description: "Data Wizard, Software Engineer, Entrepreneur",
  },
  openGraph: {
    siteName: "Seb Wiechers",
    type: "website",
    url: "https://swiechers.nl",
    title: "Seb Wiechers",
    description: "Data Wizard, Software Engineer, Entrepreneur",
    images: "https://swiechers.nl/og_image.JPG",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${font.className}`}>
        <MainLayout>{children}</MainLayout>
      </body>
    </html>
  );
}
