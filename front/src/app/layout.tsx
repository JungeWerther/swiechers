import MainLayout from "@/components/MainLayout";
import type { Metadata } from "next";
import { DM_Mono, DM_Sans, Red_Hat_Display } from "next/font/google";
import "./globals.css";

const font = DM_Mono({
  subsets: ["latin"],
  weight: "400",
});

export const metadata: Metadata = {
  title: "Create Next App",
  description: "Generated by create next app",
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