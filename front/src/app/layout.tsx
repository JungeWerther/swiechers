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
