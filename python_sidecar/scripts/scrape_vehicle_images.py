"""
Web scraper for Indian commercial vehicle images.

Strategy:
1. PRIMARY: Download directly from OEM websites (Ashok Leyland, BharatBenz, Mahindra)
2. SECONDARY: icrawler (Bing) for supplemental images per class

Usage:
    python scripts/scrape_vehicle_images.py                    # default: top classes, OEM + Bing
    python scripts/scrape_vehicle_images.py --class-id ashok_leyland_boss --max-per-class 100
    python scripts/scrape_vehicle_images.py --all --max-per-class 80
    python scripts/scrape_vehicle_images.py --oem-only         # only download from manufacturer sites
    python scripts/scrape_vehicle_images.py --list

Output: ~/.weighbridge/vehicle_captures/ (pre-labeled, ready for training)
"""

import argparse
import hashlib
import io
import json
import logging
import os
import shutil
import ssl
import tempfile
import time
import urllib.request
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

ssl._create_default_https_context = ssl._create_unverified_context

CAPTURES_DIR = Path.home() / ".weighbridge" / "vehicle_captures"
LABELS_FILE = CAPTURES_DIR / "labels.jsonl"

# =============================================================================
# OEM DIRECT IMAGE SOURCES
# These are confirmed working URLs from manufacturer websites.
# Much higher quality than Bing search results.
# =============================================================================

OEM_IMAGES = {
    # --- TATA TRUCKS (trucks.tatamotors.com) ---
    "tata_prima": [
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Prima%205532%20S%203.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Signa%205532.S-3%202.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Prima%202832.K%20Scoop%20New%20Fascia_Mer%202_0.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Prima%202832.K%20Scoop%20New%20Fascia_Mer%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Prima%203532.K%20Co-driver_Mer%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Prima%203532.K%20Co-driver_Mer%202_0.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2025-03/2830.jpeg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2023-12/Prima%202830.K%20Scoop%20SRT%20New%20Fascia_Mer.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2025-03/tata-prima-3530k-hrt.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2025-03/Prima%203530.K%20co-driver.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/PRIMA%204832.T%20Mer%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Prima%202832.K%20RMC_Mer%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Prima%203532.K%20RMC%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Prima%203530.K%20LNG%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Prima%205530.S%20LNG%20BG%20Truck%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Tata%20Prima%20E.55S%20-%201%203.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/EV_Drivers%20side_%207.12.232135%203.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/PRIMA%20EV%2028E%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/TATA%20Motors%202830.K-nameplates%2014.jpg",
    ],
    "tata_signa": [
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-1923K.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-2821T.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-2823T.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%203521.T%20Merge%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%203123.T%20Merge%202_1.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%203523.T%20Merge%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-3125T.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-3525T.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-4225T.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Signa%204932.T-1%202.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2025-03/Signa%204830.T%20Merge%20copy%281%29.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%204023.S%20Container%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-4021S.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-4025S.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-12/signa-4623s-bnr.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%205521.S%204x2%20Merge%20copy%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Signa%203023.T-2%202.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Signa%203725.T-2%202.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Signa%204425.T-2%202.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA%202830.K.png",
    ],
    "tata_signa_tipper": [
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%202832.K-TK%20Merge%201.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%204232.TK%20Merge%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%204832.TK%20Merge%20New%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/SIGNA-4830TK.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%202832.K%20REPTO%20RMC%20Merge%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/SIgna%202821.K%20RMC%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%202818.K%20RMC%202.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/Signa%202820.K%20RMC%20CNG%20Final%20Mer%202.png",
    ],
    "tata_ultra": [
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2025-04/ultra-t6.webp",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2023-10/Ultra%20T.7.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Ultra%20T.19%20Vehicle%20Image%203.jpg",
    ],
    "tata_lpt": [
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/LPT-709-G.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/LPT-712.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-02/1916-lpt.png",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/LPK%202821.K.png",
    ],
    "tata_lpk_tipper": [
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2024-09/lpk-1416.jpg",
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-04/LPK%202821.K.png",
    ],
    "tata_azura": [
        "https://trucks.tatamotors.com/assets/trucks/files/Products/2026-01/Azura%201918-3%202.jpg",
    ],

    # --- TATA SMALL TRUCKS (smalltrucks.tatamotors.com) ---
    "tata_ace": [
        "https://smalltrucks.tatamotors.com/assets/smalltrucks/files/2026-04/ace.webp",
        "https://smalltrucks.tatamotors.com/assets/smalltrucks/files/2025-10/Tata%20Ace%20Pro.jpg",
        "https://smalltrucks.tatamotors.com/assets/smalltrucks/files/2025-10/Tata%20Ace%20Gold.jpg",
        "https://smalltrucks.tatamotors.com/assets/smalltrucks/files/2025-05/ACE%20EV-1000%20-%2003_3.webp",
    ],
    "tata_intra": [
        "https://smalltrucks.tatamotors.com/assets/smalltrucks/files/2026-04/yodha%20%281%29.webp",
    ],
    "tata_yodha": [
        "https://smalltrucks.tatamotors.com/assets/smalltrucks/files/2026-04/yodha_optimized_new.webp",
        "https://smalltrucks.tatamotors.com/assets/smalltrucks/files/2025-01/Tata%20Pickup.png",
    ],

    # --- ASHOK LEYLAND ---
    "ashok_leyland_boss": [
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/04/BOSS-1115HB.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/Boss-banner.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/Boss-LX-1.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2025/11/BOSS-1920H.jpg",
    ],
    "ashok_leyland_ecomet": [
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/04/ecomet-1015HE.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/04/ecomet-1015TE-Tipper.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/Ecomet-banner.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/1815HE.jpg",
    ],
    "ashok_leyland_captain": [
        "https://www.ashokleyland.com/backend/wp-content/uploads/2025/11/AVTR-2820H-1.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/4825-HN.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2025/11/AVTR-3525H-LA.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/AVTR-2820H.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/04/AVTR-5525A-6X4.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/04/AVTR-5525A-4X2.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/04/AVTR-4020A-4X2.jpg",
    ],
    "ashok_leyland_partner": [
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/04/Partner-Super-914.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/Partner-Super-banner.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/Partner-Super-Isometric-1-1.jpg",
    ],
    "ashok_leyland_tipper": [
        "https://www.ashokleyland.com/backend/wp-content/uploads/2025/11/AVTR-3525T.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2025/11/AVTR-4825T.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2025/11/AVTR-2820-RMC.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2025/11/Cargo-2820-RMC.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/02/8x4-1.jpg",
        "https://www.ashokleyland.com/backend/wp-content/uploads/2024/03/RMC-Cargo-Cabin-1-1.jpg",
    ],

    # --- BHARATBENZ ---
    "bharatbenz_heavy": [
        "https://www.bharatbenz.com/uploads/truck_images/product_types/BB1117Rnew.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/BB1217Rnew.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/BB1217REnew.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/BB1417Rnew.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/BB1417REnew.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/BB1617Rnew.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/BB1917Rnew.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/2826-thumb.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/3526-thumb.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/3832-thumb.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/4232-thumb.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/4832-thumb.png",
        "https://www.bharatbenz.com/uploads/product_images/truck-mdt.png",
        "https://www.bharatbenz.com/uploads/product_images/truck-hdtr.png",
        "https://www.bharatbenz.com/uploads/product_images/truck-hdt-rt.png",
    ],
    "bharatbenz_tipper": [
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_bbf55e739260b74330d2266c28a9fc56.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_c05f1b942e054232d44d79308f2dbd51.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_ae49c38ceaeb623ebe5493fd0bb47e09.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_8157be9fe7036d4cfe71bf21c0cb5ca2.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_cfbf60435c8d6a525b32c89a6653f0e1.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_8008debf57d8b173ff31b41e907f779b.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_19a1459d1f6507a3a789f25f2df2d4cc.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_3148ace3e91c0b2ddb7b612da4f4671a.png",
        "https://www.bharatbenz.com/uploads/product_images/truck-hdtc.png",
    ],
    "bharatbenz_tractor": [
        "https://www.bharatbenz.com/uploads/truck_images/product_types/THUMBN_IMG_4023T.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/4028T Thumbnail.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/WEB_BANNER_4828T.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/THUMBN_IMG_5528 4x2.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/4032T Thumbnail.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/THUMBN_IMG_5032T (1).png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/5432T.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/5532T Thumbnail.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_eddfefeed71e68ab38151d47499c3644.png",
        "https://www.bharatbenz.com/uploads/truck_images/product_types/main_d78caacd5f1d8c5f3e34ca864de62fa7.png",
        "https://www.bharatbenz.com/uploads/product_images/truck-hdtt.png",
    ],

    # --- MAHINDRA TRUCK AND BUS ---
    "mahindra_blazo": [
        "https://www.mahindratruckandbus.com/english/images/hcv-img.jpg",
        "https://www.mahindratruckandbus.com/english/images/Range-Banner-desktop.jpg",
    ],
    "mahindra_furio": [
        "https://www.mahindratruckandbus.com/english/images/icv-img.jpg",
    ],
    "mahindra_bolero_pickup": [
        "https://www.mahindratruckandbus.com/english/images/lcv-img.jpg",
    ],
}

# Bing search queries (supplemental — used after OEM images)
SEARCH_QUERIES = {
    "tata_prima": [
        "Tata Prima 4928 truck front view India road",
        "Tata Prima heavy duty truck highway India",
        "Tata Prima LX truck side view loaded",
        "Tata Prima cabin truck weighbridge",
    ],
    "tata_signa": [
        "Tata Signa 4923 truck front India",
        "Tata Signa heavy truck highway India",
        "Tata Signa 2518 truck side view loaded",
        "Tata Signa tipper truck India construction",
    ],
    "tata_ultra": [
        "Tata Ultra T7 truck India road",
        "Tata Ultra medium truck delivery India",
        "Tata Ultra truck front view India",
    ],
    "tata_lpt": [
        "Tata LPT 1613 truck India highway",
        "Tata LPT cargo truck loaded India",
        "Tata LPT 2518 truck road India",
    ],
    "tata_intra": [
        "Tata Intra V10 V20 mini truck India",
        "Tata Intra small commercial vehicle India road",
        "Tata Intra pickup truck loaded India",
    ],
    "tata_ace": [
        "Tata Ace Gold mini truck India road",
        "Tata Ace HT Plus truck India",
        "Tata Ace chota hathi truck front India",
    ],
    "tata_yodha": [
        "Tata Yodha pickup truck India highway",
        "Tata Yodha 2.0 pickup front view India",
    ],
    "tata_lpk_tipper": [
        "Tata LPK tipper truck construction India",
        "Tata tipper truck loaded sand gravel India",
        "Tata LPK 1615 tipper side view India",
    ],
    "tata_signa_tipper": [
        "Tata Signa tipper truck India construction",
        "Tata Signa 1923K tipper loaded India",
    ],
    "ashok_leyland_boss": [
        "Ashok Leyland Boss truck road India",
        "Ashok Leyland Boss 1920 heavy truck India",
        "Ashok Leyland Boss ICV truck India",
    ],
    "ashok_leyland_captain": [
        "Ashok Leyland AVTR truck India highway",
        "Ashok Leyland Captain 4923 truck India",
        "Ashok Leyland heavy truck haulage India",
    ],
    "ashok_leyland_ecomet": [
        "Ashok Leyland Ecomet truck India road",
        "Ashok Leyland Ecomet 1215 truck India",
    ],
    "ashok_leyland_dost": [
        "Ashok Leyland Dost Plus mini truck India",
        "Ashok Leyland Bada Dost small truck India",
    ],
    "ashok_leyland_tipper": [
        "Ashok Leyland tipper truck India construction",
        "Ashok Leyland 2518 tipper loaded India",
        "Ashok Leyland AVTR tipper India",
    ],
    "bharatbenz_heavy": [
        "BharatBenz heavy duty truck India highway",
        "BharatBenz 2826 3526 truck India road",
        "BharatBenz truck front view India",
    ],
    "bharatbenz_tipper": [
        "BharatBenz tipper truck India construction",
        "BharatBenz 2523C tipper loaded India",
    ],
    "bharatbenz_tractor": [
        "BharatBenz tractor trailer truck India",
        "BharatBenz 5528T truck highway India",
    ],
    "eicher_pro": [
        "Eicher Pro truck India road highway",
        "Eicher Pro 6049 3015 truck front India",
        "Eicher Pro series commercial truck India",
    ],
    "volvo_fm": [
        "Volvo FM truck India highway",
        "Volvo FMX truck India construction",
        "Volvo truck India front view cabin",
    ],
    "scania_truck": [
        "Scania truck India highway",
        "Scania P410 R500 truck India",
    ],
    "mahindra_blazo": [
        "Mahindra Blazo X truck India highway",
        "Mahindra Blazo X 48 heavy truck India",
        "Mahindra Blazo truck front view India",
    ],
    "mahindra_furio": [
        "Mahindra Furio truck India road",
        "Mahindra Furio 12 14 ICV truck India",
    ],
    "mahindra_arjun": [
        "Mahindra Arjun tractor front view India field",
        "Mahindra Arjun Novo 605 tractor India",
        "Mahindra Arjun red tractor India",
    ],
    "mahindra_yuvo": [
        "Mahindra Yuvo tractor India field",
        "Mahindra Yuvo 575 415 tractor front India",
    ],
    "mahindra_bolero_pickup": [
        "Mahindra Bolero Pickup truck India road",
        "Mahindra Bolero Maxi truck cargo India",
    ],
    "sonalika_tractor": [
        "Sonalika tractor India front field",
        "Sonalika DI Tiger tractor India",
        "Sonalika Worldtrac 60 75 tractor India",
    ],
    "swaraj_tractor": [
        "Swaraj tractor India front view field",
        "Swaraj 744 855 tractor Punjab India",
        "Swaraj tractor red body India",
    ],
    "john_deere_tractor": [
        "John Deere tractor India field",
        "John Deere 5310 5045D India",
        "John Deere green tractor front India",
    ],
    "new_holland_tractor": [
        "New Holland tractor India blue field",
        "New Holland 3630 5500 tractor front India",
    ],
    "tafe_tractor": [
        "TAFE tractor India field",
        "TAFE 45DI 5900 tractor red India",
    ],
    "tanker_generic": [
        "fuel tanker truck India highway road",
        "water tanker truck India road",
        "oil tanker truck India cylindrical",
    ],
    "cement_mixer": [
        "concrete cement mixer truck India road",
        "transit mixer RMC truck India construction",
        "cement mixer rotating drum truck India",
    ],
    "trailer_flatbed": [
        "flatbed trailer truck India highway loaded",
        "multi axle trailer truck India",
        "open body trailer truck India cargo",
    ],
    "container_truck": [
        "container truck India port highway",
        "shipping container trailer truck India",
    ],
}


def download_oem_image(url: str, class_id: str) -> bool:
    """Download a single image from an OEM website."""
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Accept": "image/*,*/*",
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()

        if len(data) < 5000:
            return False

        from PIL import Image
        img = Image.open(io.BytesIO(data))
        if img.size[0] < 100 or img.size[1] < 100:
            return False

        img = img.convert("RGB")
        img_hash = hashlib.md5(data).hexdigest()[:12]

        dest = CAPTURES_DIR / f"{img_hash}.jpg"
        if dest.exists():
            return False

        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=90)
        dest.write_bytes(buf.getvalue())

        record = {
            "id": img_hash,
            "timestamp": time.time(),
            "labeled": True,
            "label": class_id,
            "labeled_at": time.time(),
            "source": f"oem:{url}",
        }
        with open(LABELS_FILE, "a") as f:
            f.write(json.dumps(record) + "\n")

        return True
    except Exception as e:
        logger.debug(f"  Failed: {url} — {e}")
        return False


def scrape_oem(class_id: str) -> int:
    """Download all OEM images for a class."""
    urls = OEM_IMAGES.get(class_id, [])
    if not urls:
        return 0

    CAPTURES_DIR.mkdir(parents=True, exist_ok=True)
    saved = 0
    for url in urls:
        if download_oem_image(url, class_id):
            saved += 1
            logger.info(f"    [OEM] Saved: {url.split('/')[-1]}")
        time.sleep(0.5)

    return saved


def scrape_bing(class_id: str, max_images: int = 50) -> int:
    """Scrape images using icrawler (Bing)."""
    try:
        from icrawler.builtin import BingImageCrawler
    except ImportError:
        logger.warning("icrawler not installed. Run: pip install icrawler")
        return 0

    queries = SEARCH_QUERIES.get(class_id, [])
    if not queries:
        return 0

    CAPTURES_DIR.mkdir(parents=True, exist_ok=True)
    saved_total = 0
    per_query = max(max_images // len(queries), 10)

    for query in queries:
        if saved_total >= max_images:
            break

        tmp_dir = tempfile.mkdtemp()
        try:
            logger.info(f"    [Bing] Searching: {query} (up to {per_query})")
            crawler = BingImageCrawler(
                storage={"root_dir": tmp_dir},
                log_level=logging.WARNING,
            )
            crawler.crawl(keyword=query, max_num=per_query)

            for fname in sorted(os.listdir(tmp_dir)):
                if saved_total >= max_images:
                    break

                fpath = os.path.join(tmp_dir, fname)
                if not os.path.isfile(fpath):
                    continue

                try:
                    from PIL import Image
                    img = Image.open(fpath)
                    if img.size[0] < 150 or img.size[1] < 150:
                        continue
                    img = img.convert("RGB")

                    with open(fpath, "rb") as f:
                        img_hash = hashlib.md5(f.read()).hexdigest()[:12]

                    dest = CAPTURES_DIR / f"{img_hash}.jpg"
                    if dest.exists():
                        continue

                    buf = io.BytesIO()
                    img.save(buf, format="JPEG", quality=85)
                    dest.write_bytes(buf.getvalue())

                    record = {
                        "id": img_hash,
                        "timestamp": time.time(),
                        "labeled": True,
                        "label": class_id,
                        "labeled_at": time.time(),
                        "source": f"bing:{query}",
                    }
                    with open(LABELS_FILE, "a") as f:
                        f.write(json.dumps(record) + "\n")

                    saved_total += 1
                except Exception:
                    continue
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

        time.sleep(1)

    return saved_total


def scrape_class(class_id: str, max_images: int = 50, oem_only: bool = False) -> int:
    """Scrape images for one vehicle class. OEM first, then Bing supplemental."""
    saved = 0

    # Step 1: OEM direct downloads (always try these first)
    oem_count = scrape_oem(class_id)
    saved += oem_count
    if oem_count > 0:
        logger.info(f"    [OEM] Got {oem_count} images from manufacturer sites")

    # Step 2: Bing supplemental (if not oem_only and still need more)
    if not oem_only and saved < max_images:
        remaining = max_images - saved
        bing_count = scrape_bing(class_id, max_images=remaining)
        saved += bing_count
        if bing_count > 0:
            logger.info(f"    [Bing] Got {bing_count} supplemental images")

    return saved


def main():
    parser = argparse.ArgumentParser(description="Scrape Indian commercial vehicle images for training")
    parser.add_argument("--class-id", help="Scrape a single class")
    parser.add_argument("--all", action="store_true", help="Scrape all classes")
    parser.add_argument("--max-per-class", type=int, default=50, help="Max images per class (default: 50)")
    parser.add_argument("--oem-only", action="store_true", help="Only download from OEM websites (no Bing)")
    parser.add_argument("--list", action="store_true", help="List available classes")
    args = parser.parse_args()

    if args.list:
        all_classes = sorted(set(list(OEM_IMAGES.keys()) + list(SEARCH_QUERIES.keys())))
        print("Available classes for scraping:")
        for cls_id in all_classes:
            oem_count = len(OEM_IMAGES.get(cls_id, []))
            bing_queries = len(SEARCH_QUERIES.get(cls_id, []))
            sources = []
            if oem_count:
                sources.append(f"{oem_count} OEM")
            if bing_queries:
                sources.append(f"{bing_queries} Bing queries")
            print(f"  {cls_id:30s} [{', '.join(sources)}]")
        print(f"\nTotal: {len(all_classes)} classes")
        print(f"OEM sources: {sum(len(v) for v in OEM_IMAGES.values())} direct URLs")
        return

    if args.class_id:
        classes_to_scrape = [args.class_id]
    elif args.all:
        classes_to_scrape = sorted(set(list(OEM_IMAGES.keys()) + list(SEARCH_QUERIES.keys())))
    else:
        # Default: most common weighbridge vehicles (prioritize classes with OEM images)
        classes_to_scrape = [
            "ashok_leyland_boss", "ashok_leyland_captain", "ashok_leyland_tipper",
            "bharatbenz_heavy", "bharatbenz_tipper", "bharatbenz_tractor",
            "mahindra_blazo",
            "tata_prima", "tata_signa", "tata_lpk_tipper",
            "tata_ace", "tata_intra",
            "tanker_generic", "cement_mixer",
            "mahindra_arjun", "sonalika_tractor",
        ]

    total_saved = 0
    for cls_id in classes_to_scrape:
        logger.info(f"\n{'='*60}")
        logger.info(f"Scraping: {cls_id} (max {args.max_per_class})")
        logger.info(f"{'='*60}")
        count = scrape_class(cls_id, max_images=args.max_per_class, oem_only=args.oem_only)
        logger.info(f"  >> Total saved for {cls_id}: {count}")
        total_saved += count

    logger.info(f"\n{'='*60}")
    logger.info(f"COMPLETE. Total images saved: {total_saved}")
    logger.info(f"Location: {CAPTURES_DIR}")

    # Show stats
    if LABELS_FILE.exists():
        from collections import Counter
        labels = []
        for line in LABELS_FILE.read_text().strip().split("\n"):
            if line:
                r = json.loads(line)
                if r.get("labeled"):
                    labels.append(r["label"])
        counts = Counter(labels)
        logger.info(f"\nClass distribution ({len(counts)} classes):")
        for cls, count in counts.most_common(20):
            bar = "#" * min(count, 50)
            logger.info(f"  {cls:30s} {count:4d} {bar}")

    logger.info(f"\nNext steps:")
    logger.info(f"  1. Review images in the labeler: http://localhost:8765/labeler")
    logger.info(f"  2. Train classifier: python scripts/train_vehicle_classifier.py")


if __name__ == "__main__":
    main()
