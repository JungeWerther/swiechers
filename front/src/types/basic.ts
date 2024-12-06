import { JSX } from "react";

export type Children = {
  children: React.ReactNode;
};

export type CMSContent = {
  [path: string]: {
    title: string;
    description?: string;
    content: string;
    link?: string;
    render?: (content: string) => Promise<JSX.Element>;
  }[];
};
