import { LaunchProps } from "@raycast/api";
import { run } from "./socket";
export default async (p: LaunchProps<{ arguments: { minutes?: string } }>) => run("focus", { min: String(parseInt(p.arguments.minutes || "25", 10) || 25) });
