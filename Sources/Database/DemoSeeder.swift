import Foundation
import GRDB

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

enum DemoSeeder {
    static func seedIfNeeded(_ dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            guard try AppSetting.value(forKey: "first_launch_seeded", db: db) == nil else { return }
            try seed(db: db)
        }
    }

    static func seed(db: Database) throws {
        var builder = SeedBuilder(db: db)
        try builder.run()
    }
}

struct SeedBuilder {
    var rng = SeededGenerator(seed: 0x5EED_CAFE)
    let db: Database
    var calendar = Calendar(identifier: .gregorian)

    var productIdsByName: [String: Int64] = [:]
    var rateByName: [String: Int64] = [:]
    var products: [Product] = []
    var customers: [Customer] = []
    var vehicles: [Vehicle] = []
    var suppliers: [Supplier] = []
var availableKg: [Int64: Int64] = [:]

    struct ProductSpec {
        var code: String
        var name: String
        var category: String
        var gstBps: Int
        var ratePaisePerTonne: Int64
        var lowKg: Int64
        var highKg: Int64
        var everyDays: Int
    }

    static let productSpecs: [ProductSpec] = [
        ProductSpec(code: "SD", name: "Stone Dust", category: "aggregate", gstBps: 500, ratePaisePerTonne: 62_000, lowKg: 80_000, highKg: 140_000, everyDays: 1),
        ProductSpec(code: "SIX", name: "6mm", category: "aggregate", gstBps: 500, ratePaisePerTonne: 68_000, lowKg: 60_000, highKg: 110_000, everyDays: 1),
        ProductSpec(code: "TEN", name: "10mm", category: "aggregate", gstBps: 500, ratePaisePerTonne: 70_000, lowKg: 120_000, highKg: 220_000, everyDays: 1),
        ProductSpec(code: "TWE", name: "20mm", category: "aggregate", gstBps: 500, ratePaisePerTonne: 69_000, lowKg: 180_000, highKg: 300_000, everyDays: 1),
        ProductSpec(code: "FOR", name: "40mm", category: "aggregate", gstBps: 500, ratePaisePerTonne: 64_000, lowKg: 40_000, highKg: 90_000, everyDays: 2),
        ProductSpec(code: "GSB", name: "GSB", category: "gsb", gstBps: 500, ratePaisePerTonne: 52_000, lowKg: 60_000, highKg: 130_000, everyDays: 2),
        ProductSpec(code: "MSD", name: "M-Sand", category: "msand", gstBps: 500, ratePaisePerTonne: 95_000, lowKg: 50_000, highKg: 100_000, everyDays: 2),
    ]

    static let operators = ["Rajesh Sawant", "Raju Gavit", "Mahesh Bhoir", "Sandeep Kadam"]
    static let businessSettings: [(String, String)] = [
        ("business_name", "Shree Vitthal Stone Crusher"),
        ("business_gstin", "27AABCS1234F1Z5"),
        ("business_address", "Survey No. 42, Village Khardi, Taluka Wada"),
        ("business_city", "Palghar"),
        ("business_state", "Maharashtra"),
        ("invoice_prefix", "INV"),
    ]

    mutating func run() throws {
        try writeSettings()
        try writeProducts()
        try writeParties()
        try writeVehicles()

        for dayIndex in 0..<30 {
            let date = day(at: dayIndex)
            try writeProduction(on: date, dayIndex: dayIndex)
            let invoiceCount = randInt(3...6)
            for _ in 0..<invoiceCount {
                try writeSale(on: date)
            }
            try writeExpenses(on: date, dayIndex: dayIndex)
        }
    }

    private func day(at index: Int) -> Date {
        let start = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: index - 29, to: start) ?? start
    }

    private mutating func writeSettings() throws {
        for entry in Self.businessSettings {
            try AppSetting.set(key: entry.0, value: entry.1, db: db)
        }
        try AppSetting.set(key: "first_launch_seeded", value: "1", db: db)
    }

    private mutating func writeProducts() throws {
        for (sortOrder, spec) in Self.productSpecs.enumerated() {
            var product = Product(
                code: spec.code,
                name: spec.name,
                category: spec.category,
                gstRateBps: spec.gstBps,
                sortOrder: sortOrder
            )
            try product.insert(db)
            guard let productID = product.id else { continue }
            productIdsByName[spec.name] = productID
            rateByName[spec.name] = spec.ratePaisePerTonne
            products.append(product)
            var rate = ProductRate(
                productId: productID,
                effectiveDate: calendar.startOfDay(for: .now),
                ratePaisePerTonne: spec.ratePaisePerTonne
            )
            try rate.insert(db)
        }
    }

    private mutating func writeParties() throws {
        let customerData: [(String, String, String, Int64, Int64)] = [
            ("Shivam Constructions", "Maharashtra", "Wada", Int64(15_000_000) * 100, Int64(400_000) * 100),
            ("Nilesh Builders & Developers", "Maharashtra", "Vasai", Int64(10_000_000) * 100, Int64(150_000) * 100),
            ("RMC Prime Concrete", "Maharashtra", "Bhiwandi", Int64(20_000_000) * 100, Int64(650_000) * 100),
            ("Ajay Procon Pvt Ltd", "Maharashtra", "Palghar", Int64(12_000_000) * 100, Int64(0)),
            ("Green Infra Projects", "Maharashtra", "Thane", Int64(18_000_000) * 100, Int64(300_000) * 100),
            ("Aakash Traders", "Maharashtra", "Manor", Int64(6_000_000) * 100, Int64(90_000) * 100),
            ("Vikas Farmhouse & Earthworks", "Maharashtra", "Dahanu", Int64(4_000_000) * 100, Int64(0)),
            ("Shree Balaji Nirman", "Maharashtra", "Murbad", Int64(8_000_000) * 100, Int64(120_000) * 100),
        ]
        for entry in customerData {
            var customer = Customer(
                name: entry.0,
                gstin: generatedGSTIN(seed: entry.0),
                phone: generatedPhone(seed: entry.0),
                address: "Plot No. \(randInt(1...999)), MIDC Road",
                city: entry.2,
                state: entry.1,
                creditLimitPaise: entry.3,
                openingBalancePaise: entry.4
            )
            try customer.insert(db)
            customers.append(customer)
        }

        let supplierData: [(String, String)] = [
            ("Bharat Petro Sales", "Thane"),
            ("Crusher Spares Depot", "Bhiwandi"),
            ("Dahiwadi Blasting Services", "Wada"),
            ("Sai Labour Services", "Vasai"),
        ]
        for entry in supplierData {
            var supplier = Supplier(
                name: entry.0,
                phone: generatedPhone(seed: entry.0),
                address: "Industrial Estate",
                city: entry.1
            )
            try supplier.insert(db)
            suppliers.append(supplier)
        }
    }

    private mutating func writeVehicles() throws {
        let vehicleData: [(String, Vehicle.Ownership, Int64, String, String)] = [
            ("MH-04-FX-1123", .own, 20_000, "Ramesh Jadhav", "9821045612"),
            ("MH-04-FX-1124", .own, 20_000, "Sunil Pawar", "9850123457"),
            ("MH-48-CY-7791", .own, 16_400, "Vikram Patil", "9967890235"),
            ("MH-12-AB-4321", .hired, 20_000, "Deepak More", "9004501123"),
            ("MH-48-DT-5502", .hired, 16_000, "Kiran Shinde", "9766332212"),
            ("MH-04-GX-9987", .hired, 26_000, "Ganesh Chavan", "9822334456"),
        ]
        for entry in vehicleData {
            var vehicle = Vehicle(
                number: entry.0,
                ownership: entry.1,
                capacityKg: entry.2,
                driverName: entry.3,
                driverPhone: entry.4
            )
            try vehicle.insert(db)
            vehicles.append(vehicle)
        }
    }

    private mutating func writeProduction(on date: Date, dayIndex: Int) throws {
        var batch = ProductionBatch(date: date, shift: dayIndex % 2 == 0 ? "A" : "B")
        batch.machineHours = Double(randInt(6...9)) + (Double(randInt(0...9)) / 10.0)
        batch.dieselLitres = Double((batch.machineHours ?? 7) * 24 + Double(randInt(-20...20)))
        batch.operatorName = Self.operators[randInt(0..<Self.operators.count)]
        try batch.insert(db)

        guard let batchID = batch.id else { return }
        for spec in Self.productSpecs where dayIndex % spec.everyDays == 0 {
            guard let productID = productIdsByName[spec.name] else { continue }
            let qty = randKg(spec.lowKg, spec.highKg)
            var item = ProductionItem(batchId: batchID, productId: productID, qtyKg: qty)
            try item.insert(db)
            availableKg[productID, default: 0] += qty
            var move = StockMovement(productId: productID, date: date, type: .production, qtyKg: qty, refId: batchID)
            try move.insert(db)
        }
    }

    private mutating func writeSale(on date: Date) throws {
        guard !customers.isEmpty, !vehicles.isEmpty, !products.isEmpty else { return }
        let customer = customers[randInt(0..<customers.count)]
        let vehicle = vehicles[randInt(0..<vehicles.count)]
        guard let customerID = customer.id else { return }

        var pool = products
        var lines: [(product: Product, qtyKg: Int64, rate: Int64)] = []
        let lineCount = randInt(1...3)
        for _ in 0..<lineCount {
            guard !pool.isEmpty else { break }
            let index = randInt(0..<pool.count)
            let product = pool.remove(at: index)
            guard let productID = product.id else { continue }
            let available = availableKg[productID] ?? 0
            let wanted = randKg(4_000, 26_000)
            let qty = min(wanted, available)
            guard qty > 2_000 else { continue }
            availableKg[productID] = available - qty
            let rate = rateByName[product.name] ?? 0
            lines.append((product, qty, rate))
        }
        guard !lines.isEmpty else { return }

        var netKg: Int64 = 0
        var itemsToPersist: [InvoiceItem] = []
        for line in lines {
            guard let productID = line.product.id else { continue }
            let amount = InvoiceCalculator.amountPaise(qtyKg: line.qtyKg, ratePaisePerTonne: line.rate)
            netKg += line.qtyKg
            itemsToPersist.append(
                InvoiceItem(
                    invoiceId: 0,
                    productId: productID,
                    qtyKg: line.qtyKg,
                    ratePaisePerTonne: line.rate,
                    amountPaise: amount,
                    gstRateBps: line.product.gstRateBps,
                    hsn: line.product.hsn
                )
            )
        }

        let transport = Int64(randInt(800...3500)) * 100
        let totals = InvoiceCalculator.totals(
            lines: lines.map {
                InvoiceCalculator.Line(qtyKg: $0.qtyKg, ratePaisePerTonne: $0.rate, gstRateBps: $0.product.gstRateBps)
            },
            transportPaise: transport,
            isIntraState: true
        )

        var invoice = SalesInvoice(
            invoiceNo: try InvoiceNumber.next(db: db, for: date),
            date: date,
            customerId: customerID,
            vehicleId: vehicle.id,
            placeOfSupply: customer.city,
            state: customer.state ?? "Maharashtra",
            status: .dispatched,
            subtotalPaise: totals.subtotalPaise,
            cgstPaise: totals.cgstPaise,
            sgstPaise: totals.sgstPaise,
            igstPaise: 0,
            transportChargePaise: transport,
            discountPaise: 0,
            grandTotalPaise: totals.grandTotalPaise
        )
        try invoice.insert(db)
        guard let invoiceID = invoice.id else { return }

        for item in itemsToPersist {
            var persisted = item
            persisted.invoiceId = invoiceID
            try persisted.insert(db)
            var move = StockMovement(productId: item.productId, date: date, type: .sale, qtyKg: -item.qtyKg, refId: invoiceID)
            try move.insert(db)
        }

        var dispatch = DispatchDetail(invoiceId: invoiceID, netKg: netKg)
        try dispatch.insert(db)

        if chance(70) {
            let full = chance(60)
            let amount = full ? totals.grandTotalPaise : totals.grandTotalPaise / 2
            let modes: [Payment.Mode] = [.cash, .cash, .upi, .upi, .upi, .cheque, .transfer]
            let mode = modes[randInt(0..<modes.count)]
            var payment = Payment(
                date: date,
                partyType: .customer,
                partyId: customerID,
                kind: .againstInvoice,
                invoiceId: invoiceID,
                amountPaise: amount,
                mode: mode,
                refNo: mode == .upi ? "UPI\(randInt(10000000...99999999))" : nil
            )
            try payment.insert(db)
        }
    }

    private mutating func writeExpenses(on date: Date, dayIndex: Int) throws {
        if dayIndex % 2 == 0 {
            let litres = Int64(randInt(500...900))
            let ratePaise = Int64(9100 + randInt(0...100))
            var purchase = Purchase(
                date: date,
                supplierId: suppliers.indices.contains(0) ? suppliers[0].id : nil,
                category: .diesel,
                amountPaise: litres * ratePaise,
                qtyLitres: Double(litres),
                ratePaise: ratePaise,
                notes: "Diesel supply"
            )
            try purchase.insert(db)
        }
        if dayIndex % 7 == 0 {
            var labour = Purchase(
                date: date,
                supplierId: suppliers.indices.contains(3) ? suppliers[3].id : nil,
                category: .labour,
                amountPaise: Int64(randInt(78_000...92_000)) * 100,
                notes: "Weekly wages"
            )
            try labour.insert(db)
            var royalty = Purchase(
                date: date,
                category: .royalty,
                amountPaise: Int64(randInt(180_000...230_000)) * 100,
                notes: "Quarry royalty paid"
            )
            try royalty.insert(db)
        }
        if dayIndex % 15 == 0 {
            var electricity = Purchase(
                date: date,
                category: .electricity,
                amountPaise: Int64(randInt(110_000...135_000)) * 100,
                notes: "MSEB bill"
            )
            try electricity.insert(db)
        }
        if dayIndex % 29 == 0 {
            var rent = Purchase(
                date: date,
                category: .rent,
                amountPaise: Int64(60_000) * 100,
                notes: "Yard rent"
            )
            try rent.insert(db)
        }
        if chance(4) {
            var parts = Purchase(
                date: date,
                supplierId: suppliers.indices.contains(1) ? suppliers[1].id : nil,
                category: .parts,
                amountPaise: Int64(randInt(8_000...28_000)) * 100,
                notes: "Wear parts"
            )
            try parts.insert(db)
        }
    }

    private mutating func randInt(_ range: ClosedRange<Int>) -> Int {
        let width = range.upperBound - range.lowerBound + 1
        return range.lowerBound + Int(rng.next() % UInt64(width))
    }

    private mutating func randInt(_ range: Range<Int>) -> Int {
        randInt(range.lowerBound...max(range.lowerBound, range.upperBound - 1))
    }

    private mutating func randKg(_ low: Int64, _ high: Int64) -> Int64 {
        let width = UInt64(high - low + 1)
        return low + Int64(rng.next() % width)
    }

    private mutating func chance(_ percent: Int) -> Bool {
        randInt(1...100) <= percent
    }

    private func generatedPhone(seed: String) -> String {
        var hash: UInt64 = 0
        for byte in seed.utf8 {
            hash = hash &* 31 &+ UInt64(byte)
        }
        let prefix = 10 + Int(hash % 70)
        let suffix = hash % 9_999_999
        return String(format: "%02d%08d", prefix, suffix)
    }

    private func generatedGSTIN(seed: String) -> String {
        var hash: UInt64 = 0
        for byte in seed.utf8 {
            hash = hash &* 31 &+ UInt64(byte)
        }
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let a = letters[Int(hash % UInt64(letters.count))]
        let b = letters[Int((hash >> 4) % UInt64(letters.count))]
        let c = letters[Int((hash >> 8) % UInt64(letters.count))]
        let digits = hash % 99_999
        return String(format: "27%@%@%@CS1%05dZ5", a, b, c, digits)
    }
}