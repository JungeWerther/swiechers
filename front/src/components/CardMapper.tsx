"use client";

import { CMSContent } from "@/types/basic";
import { useRouter } from "next/navigation";

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "./ui/card";
import { ArrowRightFromLine } from "lucide-react";
import { MarkdownRenderer } from "./MarkdownRenderer";

export function CardMapper({ items }: CMSContent) {
  const router = useRouter();

  return (
    <div className="flex flex-col gap-2 w-full h-full items-center">
      {items.map(({ title, description, content, link }, i) => {
        return (
          <Card
            key={title}
            className={`border-0 rounded-lg ${
              link && "cursor-pointer"
            } hover:bg-white bg-opacity-80 bg-black hover:text-black text-white ${
              i != 0 ? "hover:bg-opacity-80 text-sm" : "text-xl"
            }`}
            onClick={() => link && router.push(link)}
          >
            <div className="flex flex-row justify-between">
              <div>
                <CardHeader>
                  <CardTitle>{title}</CardTitle>
                  <CardDescription>{description}</CardDescription>
                </CardHeader>
                <CardContent>
                  <MarkdownRenderer content={content} />
                </CardContent>
              </div>
              {link && (
                <div className="bg-transparent rounded-r-md hover:bg-white text-gray-500 p-10 w-[200] items-center flex right-0">
                  <ArrowRightFromLine />
                </div>
              )}
            </div>
          </Card>
        );
      })}
    </div>
  );
}
