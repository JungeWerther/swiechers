"use client";

// libraries
import DOMPurify from "isomorphic-dompurify";
import { marked } from "marked";
import styles from "@/styles/MarkdownRenderer.module.css";

const parseMarkdown = (text: string) => {
  return DOMPurify.sanitize(
    marked.parse(text, {
      async: false,
    })
  );
};

export function MarkdownRenderer({ content }: { content: string }) {
  return (
    <div
      className={`${styles.__ps_markdown} gap-2 flex flex-col`}
      dangerouslySetInnerHTML={{
        __html: parseMarkdown(content),
      }}
    ></div>
  );
}
