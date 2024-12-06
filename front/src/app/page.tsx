"use client";
import { CardMapper } from "@/components/MarkdownRenderer";
import { content } from "@/constants/cms";

export default function Home() {
  return <CardMapper items={content.app} />;
}
