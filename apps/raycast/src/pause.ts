import { LaunchProps } from "@raycast/api";
import { run } from "./socket";
export default async (p: LaunchProps<{ arguments: { minutes?: string } }>) => run("pause", { min: String(parseInt(p.arguments.minutes || "30", 10) || 30) });
