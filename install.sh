#!/bin/bash

# Terminali värvid
ROHELINE='\033[0;32m'
KOLLANE='\033[1;33m'
PUNANE='\033[0;31m'
NC='\033[0m'

# Funktsioon "Vajuta suvalist klahvi, et väljuda"
press_any_key_exit() {
    echo -e "\n${KOLLANE}Vajuta suvalist klahvi, et väljuda...${NC}"
    read -n 1 -s
    clear
    exit 1
}

clear
echo -e "${ROHELINE}==================================================${NC}"
echo -e "${ROHELINE}          HIDENSEEK ESMANE PAIGALDUS              ${NC}"
echo -e "${ROHELINE}==================================================${NC}"

# ==================================================
# 1. VAADE: ROOT KONTROLL
# ==================================================
echo -e "${KOLLANE}[1/4] Õiguste kontroll...${NC}"

if [ "$EUID" -eq 0 ]; then
    echo -e "${ROHELINE}[OK] Kasutajal on piisavad õigused (Root/Sudo).${NC}"
else
    echo -e "${PUNANE}[VIGA] Skripti käivitamiseks on vaja sudo õigusi!${NC}"
    echo -e "Palun käivita skript käsuga: sudo ./install.sh"
    press_any_key_exit
fi

# ==================================================
# 2. VAADE: ANSIBLE KONTROLL JA PAIGALDUS
# ==================================================
echo -e "\n${KOLLANE}[2/4] Ansible kontroll...${NC}"

if command -v ansible-playbook &> /dev/null; then
    ANSIBLE_VER=$(ansible --version | head -n 1 | awk '{print $2}')
    echo -e "${ROHELINE}[OK] Ansible on juba paigaldatud (Versioon: $ANSIBLE_VER).${NC}"
else
    echo -e "${KOLLANE}[INFO] hideNseek paigaldamiseks on enne vaja paigaldada Ansible.${NC}"

    # Küsime kasutajalt kinnitust (jaa või ei)
    read -p "Kas soovid, et skript paigaldaks Ansible automaatselt? (j/e): " VASTUS

    if [[ "$VASTUS" =~ ^[JjYy]$ ]]; then
        echo -e "\nAlustan Ansible paigaldamist, palun oota..."

        # Paigaldame vajalikud paketid vaikselt
        apt-get update -y > /dev/null
        apt-get install -y software-properties-common curl git whiptail > /dev/null
        apt-add-repository -y ppa:ansible/ansible > /dev/null
        apt-get update -y > /dev/null
        apt-get install -y ansible > /dev/null

        # Kontrollime, kas paigaldus õnnestus ja kuvame versiooni
        if command -v ansible-playbook &> /dev/null; then
            ANSIBLE_VER=$(ansible --version | head -n 1 | awk '{print $2}')
            echo -e "${ROHELINE}[OK] Ansible on edukalt paigaldatud! (Versioon: $ANSIBLE_VER)${NC}"
        else
            echo -e "${PUNANE}[VIGA] midagi läks Ansible paigaldamisel valesti.${NC}"
            press_any_key_exit
        fi
    else
        echo -e "${PUNANE}\n[INFO] Toimub väljumine, kuna Ansiblet ei lubatud paigaldada.${NC}"
        press_any_key_exit
    fi
fi

# ==================================================
# 3. VAADE: SCRIPTIDE KOPEERIMINE ETTENÄHTUD KAUSTA
# ==================================================
echo -e "\n${KOLLANE}[3/4] Failide kopeerimine süsteemi...${NC}"

SIHTKAUST="/usr/share/hidenseek"

# KONTROLL: Kas 'data' kaust üldse eksisteerib install.sh kõrval?
if [ ! -d "./data" ]; then
    echo -e "${PUNANE}[VIGA] Ei leidnud kausta 'data'!${NC}"
    echo -e "Veendu, et käivitad install.sh faili otse selle õigest kaustast."
    press_any_key_exit
fi

# Teeme kindlaks, et sihtkaust on puhas ja olemas
mkdir -p "$SIHTKAUST"

# Kopeerime kõik failid praegusest kaustast sihtkausta
cp -r ./data/* "$SIHTKAUST/"

if [ $? -eq 0 ]; then
    echo -e "${ROHELINE}[OK] Kõik Ansible skriptid on kopeeritud kausta: $SIHTKAUST${NC}"
else
    echo -e "${PUNANE}[VIGA] Failide kopeerimine ebaõnnestus.${NC}"
    press_any_key_exit
fi

# ==================================================
# 4. VAADE: GLOBAALSE KÄSU LOOMINE
# ==================================================
echo -e "\n${KOLLANE}[4/4] Globaalse käsu 'hidenseek' loomine...${NC}"

# Luuakse Ansible Vault jaoks salajane master-võti (ainult root pääseb ligi)
VAULT_VOTI="/root/.hidenseek_vault"
if [ ! -f "$VAULT_VOTI" ]; then
    openssl rand -base64 32 > "$VAULT_VOTI"
    chmod 600 "$VAULT_VOTI"
    echo -e "${ROHELINE}[OK] Süsteemi krüptovõti on loodud asukohta $VAULT_VOTI${NC}"
fi

KASU_FAIL="/usr/local/bin/hidenseek"

# Loome käivitusfaili, mis liigub alati õigesse kopeeritud kausta
cat <<EOF > "$KASU_FAIL"
#!/bin/bash
cd $SIHTKAUST
sudo ./main.sh "\$@"
EOF

# Anname globaalsele käsule käivitusõigused
chmod +x "$KASU_FAIL"

# Anname igaks juhuks käivitusõiguse ka kopeeritud GUI skriptile
chmod +x "$SIHTKAUST/main.sh"

if [ -f "$KASU_FAIL" ]; then
    echo -e "${ROHELINE}[OK] Globaalne käsk 'hidenseek' on edukalt loodud!${NC}"
else
    echo -e "${PUNANE}[VIGA] Globaalse käsu loomine ebaõnnestus.${NC}"
    press_any_key_exit
fi

# LÕPETAMINE
echo -e "\n${ROHELINE}==================================================${NC}"
echo -e "${ROHELINE}        ESMANE ETTEVALMISTUS ON TEHTUD!           ${NC}"
echo -e "${ROHELINE}==================================================${NC}"
echo -e "Nüüd võid selle esmase kausta ära kustutada või sulgeda."
echo -e "SOC halduskeskkonna avamiseks kirjuta käsureal lihtsalt:\n"
echo -e "   ${KOLLANE}hidenseek${NC}\n"