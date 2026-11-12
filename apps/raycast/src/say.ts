import { LaunchProps } from "@raycast/api";
import { run } from "./socket";
export default async (p: LaunchProps<{ arguments: { text: string } }>) => run("say", { text: p.arguments.text.slice(0, 80) });
