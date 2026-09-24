import SwiftUI

enum SidebarDestination: Hashable, Identifiable {
    case overview
    case production
    case invoices
    case payments
    case purchases
    case stock
    case reports
    case products
    case customers
    case suppliers
    case vehicles
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Dashboard"
        case .production: "Production"
        case .invoices: "Sales & Invoices"
        case .payments: "Payments"
        case .purchases: "Purchases"
        case .stock: "Stock"
        case .reports: "Reports"
        case .products: "Products"
        case .customers: "Customers"
        case .suppliers: "Suppliers"
        case .vehicles: "Vehicles"
        case .settings: "Settings & Backup"
        }
    }

    var icon: String {
        switch self {
        case .overview: "chart.pie"
        case .production: "gearshape.2"
        case .invoices: "doc.text"
        case .payments: "indianrupeesign"
        case .purchases: "cart"
        case .stock: "shippingbox"
        case .reports: "doc.plaintext"
        case .products: "cube.box"
        case .customers: "person.2"
        case .suppliers: "truck.box"
        case .vehicles: "truck.pickup.side"
        case .settings: "gearshape"
        }
    }

    static let operations: [SidebarDestination] = [.production, .invoices, .payments]
    static let resources: [SidebarDestination] = [.purchases, .stock]
    static let masters: [SidebarDestination] = [.products, .customers, .suppliers, .vehicles]
    static let financial: [SidebarDestination] = [.reports]
    static let system: [SidebarDestination] = [.settings]
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        if let launchError = appState.launchError {
            // The database failed to open and the app is on a throwaway
            // in-memory copy: block the UI rather than silently lose work.
            LaunchErrorView(message: launchError) {
                appState.retryOpen()
            }
        } else {
            NavigationSplitView {
                sidebar($appState.selectedDestination)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
            } detail: {
                detail
            }
        }
    }

    private func sidebar(_ selection: Binding<SidebarDestination?>) -> some View {
        List(selection: selection) {
            brand
            sidebarSection("Overview", items: [.overview])
            sidebarSection("Operations", items: SidebarDestination.operations)
            sidebarSection("Resources", items: SidebarDestination.resources)
            sidebarSection("Master Data", items: SidebarDestination.masters)
            sidebarSection("Insights", items: SidebarDestination.financial)
            sidebarSection("System", items: SidebarDestination.system)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(DS.Color.sidebar)
    }

    @ViewBuilder
    private var brand: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                Text("PaashERP")
                    .font(DS.Font.sectionTitle)
                    .foregroundStyle(DS.Color.sidebarText)
            }
            Text("Stone Crusher Unit · ERP")
                .font(DS.Font.footnote)
                .foregroundStyle(DS.Color.sidebarMuted)
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.s)
    }

    private func sidebarSection(_ title: String, items: [SidebarDestination]) -> some View {
        Section {
            ForEach(items) { item in
                SidebarRow(item: item)
            }
        } header: {
            Text(title.uppercased())
                .font(DS.Font.groupLabel)
                .foregroundStyle(DS.Color.sidebarMuted)
        }
        .listRowBackground(DS.Color.sidebar)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedDestination {
        case .overview:
            OverviewView()
        case .production:
            ProductionModuleView()
        case .invoices:
            SalesModuleView()
        case .payments:
            PaymentsModuleView()
        case .purchases:
            PurchasesModuleView()
        case .stock:
            StockModuleView()
        case .reports:
            ReportsModuleView()
        case .products:
            ProductsView()
        case .customers:
            CustomersView()
        case .suppliers:
            SuppliersView()
        case .vehicles:
            VehiclesView()
        case .settings:
            SettingsView()
        case nil:
            OverviewView()
        }
    }
}

private struct SidebarRow: View {
    let item: SidebarDestination

    var body: some View {
        Label {
            Text(item.title)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.sidebarText)
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(DS.Color.sidebarMuted)
        }
        .tag(item)
        .padding(.vertical, 2)
    }
}

/// Shown when the database could not be opened at launch. The app must not be
/// used in this state, since everything would be written to a temporary
/// in-memory database and lost on quit.
private struct LaunchErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(DS.Color.danger)
            Text("Your data could not be opened")
                .font(DS.Font.sectionTitle)
            Text("PaashERP is running on a temporary in-memory copy, so nothing you do now will be saved. Quit immediately if you need to avoid losing entries, then check the message below before trying again.")
                .font(DS.Font.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DS.Font.footnote)
                .foregroundStyle(DS.Color.danger)
                .textSelection(.enabled)
                .frame(maxWidth: 460)
            Button("Try opening again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.contentBackground)
    }
}