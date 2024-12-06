"use server";
import { MarkdownRenderer } from "@/components/MarkdownRenderer";

export async function markdownRender(content: string) {
  return <MarkdownRenderer content={content} />;
}
