plugins {
    id("com.android.asset-pack")
}

assetPack {
    packName = "samples_pack"
    dynamicDelivery {
        deliveryType = "install-time"
    }
}
