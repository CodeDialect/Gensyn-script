#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Banner
clear
echo -e "${GREEN}"
cat << "BANNER"
 ______              _         _                                             
|  ___ \            | |       | |                   _                        
| |   | |  ___    _ | |  ____ | | _   _   _  ____  | |_   ____   ____  _____ 
| |   | | / _ \  / || | / _  )| || \ | | | ||  _ \ |  _) / _  ) / ___)(___  )
| |   | || |_| |( (_| |( (/ / | | | || |_| || | | || |__( (/ / | |     / __/ 
|_|   |_| \___/  \____| \____)|_| |_| \____||_| |_| \___)\____)|_|    (_____)
                                                                             
BANNER
echo -e "${NC}"

echo -e "${GREEN}[1/9] Updating system...${NC}"
sudo apt-get update && sudo apt-get upgrade -y

echo -e "${GREEN}[2/9] Installing dependencies...${NC}"
sudo apt install -y sudo nano curl python3 python3-pip python3-venv git screen

echo -e "${GREEN}[3/9] Installing NVM and latest Node.js...${NC}"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install node
nvm use node

echo -e "${GREEN}[4/9] Cloning rl-swarm repository...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm
cd rl-swarm

echo -e "${GREEN}[5/9] Setting up Python virtual environment...${NC}"
python3 -m venv .venv
source .venv/bin/activate

echo -e "${GREEN}[6/9] Replacing app/page.tsx with custom content...${NC}"
mkdir -p modal-login/app
cat > modal-login/app/page.tsx << 'EOF'
"use client";
import {
  useAuthModal,
  useLogout,
  useSigner,
  useSignerStatus,
  useUser,
} from "@account-kit/react";
import { useEffect, useState } from "react";

export default function Home() {
  const user = useUser();
  const { openAuthModal } = useAuthModal();
  const signerStatus = useSignerStatus();
  const { logout } = useLogout();
  const signer = useSigner();

  const [createdApiKey, setCreatedApiKey] = useState(false);

  useEffect(() => {
    console.log("signerStatus:", signerStatus);
    console.log("user:", user);
    console.log("createdApiKey:", createdApiKey);
  }, [signerStatus, user, createdApiKey]);

  useEffect(() => {
    if (!user && createdApiKey) {
      setCreatedApiKey(false);
    }
    if (!user || !signer || !signerStatus.isConnected || createdApiKey) return;

    const submitStamp = async () => {
      const whoamiStamp = await signer.inner.stampWhoami();
      const resp = await fetch("/api/get-api-key", {
        method: "POST",
        body: JSON.stringify({ whoamiStamp }),
      });
      return (await resp.json()) as { publicKey: string };
    };

    const createApiKey = async (publicKey: string) => {
      await signer.inner.experimental_createApiKey({
        name: `server-signer-${Date.now()}`,
        publicKey,
        expirationSec: 60 * 60 * 24 * 62,
      });
    };

    const handleAll = async () => {
      try {
        const { publicKey } = await submitStamp();
        await createApiKey(publicKey);
        await fetch("/api/set-api-key-activated", {
          method: "POST",
          body: JSON.stringify({ orgId: user.orgId, apiKey: publicKey }),
        });
        setCreatedApiKey(true);
      } catch (err) {
        console.error("API Key Setup Error:", err);
        alert("Something went wrong during API key setup.");
      }
    };

    handleAll();
  }, [createdApiKey, signer, signerStatus.isConnected, user]);

  useEffect(() => {
    if (typeof window !== "undefined") {
      try {
        if (typeof window.crypto.subtle !== "object") {
          throw new Error("window.crypto.subtle is not available");
        }
      } catch (err) {
        alert(
          "Crypto API is not available. Please access via localhost or HTTPS."
        );
      }
    }
  }, []);

  useEffect(() => {
    if (!signerStatus.isInitializing && !user) {
      openAuthModal();
    }
  }, [signerStatus.isInitializing, user]);

  return (
    <main className="flex min-h-screen flex-col items-center gap-4 justify-center text-center">
      {signerStatus.isInitializing ? (
        <p className="text-lg font-medium">Initializing signer...</p>
      ) : user && !createdApiKey ? (
        <p className="text-lg font-medium">Creating API key...</p>
      ) : user ? (
        <div className="card">
          <div className="flex flex-col gap-2 p-2">
            <p className="text-xl font-bold">
              YOU ARE SUCCESSFULLY LOGGED IN TO THE GENSYN TESTNET
            </p>
            <button className="btn btn-primary mt-6" onClick={() => logout()}>
              Log out
            </button>
          </div>
        </div>
      ) : (
        <div className="card">
          <p className="text-xl font-bold">LOGIN TO THE GENSYN TESTNET</p>
          <div className="flex flex-col gap-2 p-2">
            <button className="btn btn-primary mt-6" onClick={openAuthModal}>
              Login
            </button>
          </div>
        </div>
      )}
    </main>
  );
}
EOF

echo -e "${GREEN}[7/9] Running ./run_rl_swarm.sh in a screen session...${NC}"
screen -dmS gensyn bash -c "source .venv/bin/activate && ./run_rl_swarm.sh"

echo -e "${GREEN}[8/9] Installing localtunnel (if not installed)...${NC}"
npm install -g localtunnel

echo -e "${GREEN}[9/9] Starting localtunnel on port 3000...${NC}"
screen -dmS localtunnel bash -c 'lt --port 3000 > lt_output.txt'
sleep 6

LT_URL=$(grep -o 'https://[^ ]*' lt_output.txt | head -n1)
rm lt_output.txt

IP=$(curl -s ifconfig.me)

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Localtunnel URL: ${LT_URL}${NC}"
echo -e "${GREEN}Use this IP as password during login: ${IP}${NC}"
echo -e "${GREEN}=========================================${NC}"
