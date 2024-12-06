import { CardMapper } from "@/components/MarkdownRenderer";
import { content } from "@/constants/cms";

export default function Page() {
  return <CardMapper items={content.bio} />;
}
