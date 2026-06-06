"use client";

// libraries
import DOMPurify from "isomorphic-dompurify";
import { Marked } from "marked";
import markedKatex from "marked-katex-extension";

// KaTeX styles for rendering LaTeX formulas
import "katex/dist/katex.min.css";
import styles from "@/styles/MarkdownRenderer.module.css";

// A dedicated marked instance with KaTeX support so we don't mutate the
// global parser. Inline math is written as $...$ and display math as $$...$$.
const marked = new Marked();
marked.use(
  markedKatex({
    throwOnError: false,
    output: "htmlAndMathml",
  })
);

const parseMarkdown = (text: string) => {
  return DOMPurify.sanitize(
    marked.parse(text, {
      async: false,
    }) as string
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
