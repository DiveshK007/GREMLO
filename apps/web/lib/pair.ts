/** The message the owner's wallet signs to pair a Mac (NEP-413). It must match the server's pairMessage byte for
 *  byte (apps/server/src/auth.ts), or the signature won't verify. */
export const pairMessage = (pet: string, device: string) => `Pair this device to my pet.\nPet: ${pet}\nDevice: ${device}`;
