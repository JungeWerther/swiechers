import { CardMapper } from "@/components/CardMapper";
import { content } from "@/constants/cms";

export default function Page() {
  return <CardMapper items={content.projects} />;
}
