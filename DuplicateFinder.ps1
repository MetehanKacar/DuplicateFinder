# Baslangic uyumluluk kontrolleri (diger PC'lerde acilis problemlerini azaltir)
$earlyLang = 'en'
try {
    $earlyTwo = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    if ($earlyTwo -and $earlyTwo.ToLower() -eq 'tr') { $earlyLang = 'tr' }
}
catch { }

if ($env:OS -ne 'Windows_NT') {
    $msgWindows = if ($earlyLang -eq 'tr') {
        "Bu uygulama sadece Windows'ta calisir."
    }
    else {
        "This application runs on Windows only."
    }
    Write-Error $msgWindows
    exit 1
}

$currentApartment = [System.Threading.Thread]::CurrentThread.ApartmentState
if ($currentApartment -ne [System.Threading.ApartmentState]::STA) {
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        $argLine = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
        Start-Process -FilePath "powershell.exe" -ArgumentList $argLine | Out-Null
        exit
    }
    else {
        $msgSta = if ($earlyLang -eq 'tr') {
            "GUI modu icin STA thread gerekli. Script'i dosyadan calistirin."
        }
        else {
            "STA thread is required for GUI mode. Run the script from a file."
        }
        Write-Error $msgSta
        exit 1
    }
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
}
catch {
    $runHint = if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        "powershell -NoProfile -ExecutionPolicy Bypass -STA -File <script.ps1>"
    }
    else {
        "powershell -NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    }

    $msg = if ($earlyLang -eq 'tr') {
        "Baslatma hatasi: WinForms kutuphaneleri yuklenemedi.`n`n$($_.Exception.Message)`n`nSunu deneyin:`n$runHint"
    }
    else {
        "Startup error: WinForms assemblies could not be loaded.`n`n$($_.Exception.Message)`n`nTry this:`n$runHint"
    }

    $title = if ($earlyLang -eq 'tr') { "Baslatma Hatasi" } else { "Startup Error" }

    Write-Error $msg
    try {
        [System.Windows.Forms.MessageBox]::Show($msg, $title, 'OK', 'Error') | Out-Null
    }
    catch { }
    exit 1
}

if (-not ("ShellThumbnailProvider" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IShellItemImageFactory
{
    [PreserveSig]
    int GetImage(SIZE size, SIIGBF flags, out IntPtr phbm);
}

[StructLayout(LayoutKind.Sequential)]
struct SIZE
{
    public int cx;
    public int cy;
}

[Flags]
enum SIIGBF
{
    RESIZETOFIT = 0x00,
    BIGGERSIZEOK = 0x01,
    MEMORYONLY = 0x02,
    ICONONLY = 0x04,
    THUMBNAILONLY = 0x08,
    INCACHEONLY = 0x10
}

public static class ShellThumbnailProvider
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(
        [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
        IntPtr pbc,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory ppv);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(IntPtr hObject);

    public static IntPtr TryGetThumbnailHBitmap(string path, int width, int height)
    {
        IShellItemImageFactory factory = null;
        IntPtr hBitmap = IntPtr.Zero;
        try
        {
            Guid iid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");
            SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out factory);

            SIZE size = new SIZE { cx = width, cy = height };
            int hr = factory.GetImage(size, SIIGBF.THUMBNAILONLY | SIIGBF.BIGGERSIZEOK, out hBitmap);
            if (hr != 0 || hBitmap == IntPtr.Zero)
            {
                hr = factory.GetImage(size, SIIGBF.BIGGERSIZEOK, out hBitmap);
                if (hr != 0 || hBitmap == IntPtr.Zero) return IntPtr.Zero;
            }

            IntPtr result = hBitmap;
            hBitmap = IntPtr.Zero;
            return result;
        }
        catch
        {
            return IntPtr.Zero;
        }
        finally
        {
            if (hBitmap != IntPtr.Zero) DeleteObject(hBitmap);
            if (factory != null) Marshal.ReleaseComObject(factory);
        }
    }

    public static void FreeHBitmap(IntPtr hBitmap)
    {
        if (hBitmap != IntPtr.Zero) DeleteObject(hBitmap);
    }
}
"@ -Language CSharp
}

# ==================== AYARLAR ====================
$script:ImgExt = @('.jpg','.jpeg','.png','.bmp','.gif','.tiff','.tif','.webp','.ico')
$script:VidExt = @('.mp4','.avi','.mkv','.mov','.wmv','.flv','.webm','.m4v','.mpg','.mpeg','.3gp','.ts')
$script:AudExt = @('.mp3','.wav','.flac','.m4a','.aac','.ogg','.wma','.opus','.aiff','.amr')
$script:AllExt = $script:ImgExt + $script:VidExt + $script:AudExt
$script:Duplicates = @{}
$script:FlatList = [System.Collections.ArrayList]::new()
$script:ThumbCache = @{}
$script:UnloadedItems = [System.Collections.ArrayList]::new()
$script:TotalThumbCount = 0
$script:IsBulkCheckUpdate = $false
$script:PathToHash = @{}
$script:HashMeta = @{}
$script:PreviewTimer = $null
$script:PreviewPath = ""
$script:BuildTimer = $null
$script:IsListBuilding = $false
$script:BuildItems = [System.Collections.ArrayList]::new()
$script:BuildIndex = 0
$script:BuildBatchSize = 140
$script:ActiveBuildBatchSize = 140
$script:ThumbsPerTick = 5
$script:MaxGroupThumbItems = 36
$script:PlaceholderThumb = $null
$script:PostBuildStatus = ""
$script:UiToolTip = $null
$script:GroupThumbTimer = $null
$script:PendingGroupIndex = -1
$script:OneStrategyCombo = $null
$script:MediaFilterCombo = $null
$script:MediaViewCache = @{}
$script:CurrentMediaMode = "all"
$script:PathToImageIndex = @{}
$script:IsFastViewSwitch = $false
$script:ModeRenderCache = @{}
$script:ScannedMediaFiles = [System.Collections.ArrayList]::new()
$script:LanguageCombo = $null
$script:LanguageLabel = $null
$script:SelectedFolderPath = ""
$script:OneStrategyKeys = @(
    "mod_newest",
    "mod_oldest",
    "created_newest",
    "created_oldest",
    "smallest_size",
    "largest_size",
    "longest_name",
    "shortest_name",
    "longest_path",
    "shortest_folder_name",
    "deepest_folder",
    "shallowest_folder"
)

function Get-DefaultLanguage {
    try {
        $two = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($two -and $two.ToLower() -eq 'tr') { return 'tr' }
    }
    catch { }
    return 'en'
}

$script:CurrentLanguage = Get-DefaultLanguage

$THUMB_W = 120
$THUMB_H = 120

# ==================== YARDIMCI ====================
function T([string]$Key, [object[]]$FormatArgs = @()) {
    $lang = if ($script:CurrentLanguage -eq 'tr') { 'tr' } else { 'en' }

    $text = switch ($lang) {
        'tr' {
            switch ($Key) {
                'app_title' { 'Kopya Dosya Bulucu  -  Resim, Video && Ses' }
                'app_header' { 'KOPYA DOSYA BULUCU' }
                'select_folder' { 'Klasor Sec' }
                'include_subfolders' { 'Alt klasorler dahil' }
                'scan' { 'TARA' }
                'language' { 'Dil' }
                'path_not_selected' { 'Klasor secilmedi...' }
                'status_ready' { '  Hazir. Klasor secip TARA butonuna basin.' }
                'auto_select' { 'OTOMATIK SEC' }
                'one_strategy' { '1 Dosya Stratejisi' }
                'view_filter' { 'Gorunum Filtresi' }
                'delete_selected_recycle' { 'SECILILERI SIL`n(Geri Donusum)' }
                'selected_count' { 'Secili: {0} dosya' }
                'selected_size' { 'Alan: {0}' }
                'preview' { 'ONIZLEME' }
                'group_files' { 'GRUPTAKI DOSYALAR' }
                'open_file' { 'Dosyayi Ac' }
                'open_folder' { 'Klasoru Ac' }

                'media_type_image' { 'Resim' }
                'media_type_video' { 'Video' }
                'media_type_audio' { 'Ses' }
                'media_type_other' { 'Diger' }

                'filter_media_all' { 'Tum Medyalar' }
                'filter_media_images' { 'Sadece Resimler' }
                'filter_media_videos' { 'Sadece Videolar' }
                'filter_media_audio' { 'Sadece Sesler' }

                'strategy_mod_newest' { 'En Yeni (Degisiklik)' }
                'strategy_mod_oldest' { 'En Eski (Degisiklik)' }
                'strategy_created_newest' { 'Olusturma En Yeni' }
                'strategy_created_oldest' { 'Olusturma En Eski' }
                'strategy_smallest_size' { 'En Kucuk Boyut' }
                'strategy_largest_size' { 'En Buyuk Boyut' }
                'strategy_longest_name' { 'En Uzun Dosya Adi' }
                'strategy_shortest_name' { 'En Kisa Dosya Adi' }
                'strategy_longest_path' { 'En Uzun Klasor Yolu' }
                'strategy_shortest_folder_name' { 'En Kisa Klasor Adi' }
                'strategy_deepest_folder' { 'En Derin Klasor' }
                'strategy_shallowest_folder' { 'En Sig Klasor' }

                'filter_pick_one_text' { 'Her Gruptan 1 Sec' }
                'filter_pick_one_desc' { 'stratejiye gore' }
                'filter_leave_one_text' { 'Her Grupta 1 Birak' }
                'filter_leave_one_desc' { 'stratejiye gore' }
                'filter_swipe_text' { 'Kaydirarak Karar' }
                'filter_swipe_desc' { 'sol:sil | sag:kalsin' }
                'filter_specific_text' { 'Belirli Klasor' }
                'filter_specific_desc' { 'klasordeki kopyalar' }
                'filter_select_all_text' { 'Tumunu Sec' }
                'filter_deselect_all_text' { 'Secimi Temizle' }

                'group_header' { 'Grup {0}  -  {1} dosya  -  Kazanc: {2}' }
                'group_more_files' { '+{0} dosya daha...' }
                'details_template' { 'Boyut: {0}  |  Tur: {1}`nTarih: {2}`nKlasor: {3}' }
                'unknown_name' { '(Isimsiz)' }

                'status_building_list' { 'Liste hazirlaniyor... {0}/{1}' }
                'status_no_duplicates_in_selected' { 'Secili turde kopya yok' }
                'status_filtering_view' { 'Gorunum filtreleniyor...' }
                'status_wait_build_filter' { 'Liste hazirlaniyor, filtre bekletildi' }
                'status_wait_build_swipe' { 'Liste hazirlaniyor, kaydirma modu bekletildi' }
                'status_opening_swipe' { 'Kaydirma modu aciliyor...' }
                'status_swipe_cancelled' { 'Kaydirma modu iptal edildi' }
                'status_filter_applying' { 'Filtre uygulaniyor...' }
                'status_thumbnails' { 'Thumbnails {0}/{1}' }

                'status_folder_selected' { '  Klasor: {0}' }
                'status_scanning_files' { '  Dosyalar taraniyor...' }
                'status_media_found' { '  {0} medya bulundu.' }
                'status_no_media_found' { '  Medya dosyasi bulunamadi.' }
                'status_no_duplicates_found' { '  Kopya bulunamadi. ({0} dosya tarandi)' }
                'status_fast_scan' { '  Hizli tarama... {0}/{1}' }
                'status_full_hash' { '  Tam hash... {0}/{1}' }
                'status_scan_summary' { '  {0} grup, {1} dosya. Kazanilacak: {2}' }

                'title_info' { 'Bilgi' }
                'title_error' { 'Hata' }
                'title_warning' { 'Uyari' }
                'title_confirm' { 'Onay' }
                'title_completed' { 'Tamamlandi' }

                'scan_folder_prompt' { 'Taranacak klasoru secin' }
                'filter_folder_prompt' { 'Bu klasordeki kopyalar secilsin' }
                'error_invalid_folder' { 'Gecersiz klasor!' }

                'delete_preview_title_default' { 'Kaydirma' }
                'delete_preview_title_suffix' { '{0} - Silinecek Dosyalar' }
                'delete_preview_help' { 'Dosyayi secince sagda onizleme gorursunuz. Del tusu veya LISTEDEN CIKAR ile secilenleri listeden alabilirsiniz.' }
                'delete_preview_col_file' { 'Dosya' }
                'delete_preview_col_size' { 'Boyut' }
                'delete_preview_col_folder' { 'Klasor' }
                'delete_preview_none_selected' { 'Dosya secilmedi' }
                'delete_preview_remove' { 'LISTEDEN CIKAR`n(Del)' }
                'delete_preview_cancel' { 'VAZGEC' }
                'delete_preview_approve' { 'ONAYLA VE SIL' }
                'delete_preview_empty' { 'Listede silinecek dosya kalmadi.' }
                'delete_preview_source_label' { 'Kaynak' }
                'delete_preview_summary' { '{0} dosya silinecek  |  Toplam: {1}{2}' }

                'delete_confirm_examples_header' { 'Secilenlerden ornekler:' }
                'delete_confirm_more_files' { ' - ... +{0} dosya daha' }
                'delete_confirm_source' { 'Kaynak: {0}' }
                'delete_confirm_message' { '{0} dosya silinecek ({1}){2}{3}`n`nDosyalar Geri Donusum Kutusuna gonderilecek.`nDevam etmek istiyor musunuz?' }
                'delete_status_deleting' { '  Siliniyor...' }
                'delete_status_error_suffix' { ', {0} hata' }
                'delete_status_done' { '  {0} dosya geri donusum kutusuna gonderildi{1}' }
                'delete_done_message' { '{0} / {1} dosya silindi.' }

                'swipe_need_scan' { 'Kaydirma modu icin once tarama yapmalisiniz.' }
                'swipe_no_media' { 'Kaydirma modu icin uygun medya dosyasi bulunamadi.' }
                'swipe_mode_title' { 'Kaydirarak Karar Modu' }
                'swipe_card_progress' { 'Kart {0}/{1}' }
                'swipe_counts' { 'Sil: 0  |  Kalsin: 0' }
                'swipe_counts_full' { 'Sil: {0}  |  Kalsin: {1}  |  Isaretlenen: {2}/{3}' }
                'swipe_decision_waiting' { 'BU KART: KARAR BEKLIYOR' }
                'swipe_decision_keep' { 'BU KART: KALSIN' }
                'swipe_decision_delete' { 'BU KART: SILINSIN' }
                'swipe_tag_waiting' { 'Karar bekliyor' }
                'swipe_tag_keep' { 'KALSIN' }
                'swipe_tag_delete' { 'SILINSIN' }
                'swipe_prev' { 'GERI`n(Backspace)' }
                'swipe_delete' { 'SILINSIN`n(Sol Ok / A)' }
                'swipe_skip' { 'ATLA`n(Bosluk)' }
                'swipe_keep' { 'KALSIN`n(Sag Ok / D)' }
                'swipe_cancel' { 'IPTAL`n(Esc)' }
                'swipe_finish' { 'BITIR`n(F)' }
                'swipe_early_finish_title' { 'Erken Bitir' }
                'swipe_early_finish_question' { 'Tum kartlar tamamlanmadi. Mevcut secimlerle bitirmek istiyor musunuz?' }
                'swipe_close_confirm' { 'Kaydirma oturumu tamamlanmadi. Cikmak istiyor musunuz?' }
                'swipe_finished_early' { 'Kaydirma erken bitirildi' }
                'swipe_finished_done' { 'Kaydirma bitti' }
                'swipe_no_delete_selection' { '{0}. Silinecek dosya secilmedi.' }
                'swipe_status_no_delete' { '{0}, silinecek secim yok' }
                'swipe_status_summary' { '{0}: silinecek {1}, kalsin {2}' }
                'swipe_delete_review_source' { 'Kaydirma modu' }
                'swipe_delete_cancelled' { '{0}, silme iptal edildi' }
                'swipe_delete_no_remaining' { '{0}, silinecek secim kalmadi' }
                'swipe_delete_empty_after_review' { 'Silme listesi bos oldugu icin islem iptal edildi.' }

                default { $Key }
            }
        }
        default {
            switch ($Key) {
                'app_title' { 'DuplicateFinder  -  Image, Video & Audio' }
                'app_header' { 'DUPLICATEFINDER' }
                'select_folder' { 'Select Folder' }
                'include_subfolders' { 'Include subfolders' }
                'scan' { 'SCAN' }
                'language' { 'Language' }
                'path_not_selected' { 'No folder selected...' }
                'status_ready' { '  Ready. Select a folder and press SCAN.' }
                'auto_select' { 'AUTO SELECT' }
                'one_strategy' { 'Single File Strategy' }
                'view_filter' { 'View Filter' }
                'delete_selected_recycle' { 'DELETE SELECTED`n(Recycle Bin)' }
                'selected_count' { 'Selected: {0} files' }
                'selected_size' { 'Space: {0}' }
                'preview' { 'PREVIEW' }
                'group_files' { 'FILES IN THIS GROUP' }
                'open_file' { 'Open File' }
                'open_folder' { 'Open Folder' }

                'media_type_image' { 'Image' }
                'media_type_video' { 'Video' }
                'media_type_audio' { 'Audio' }
                'media_type_other' { 'Other' }

                'filter_media_all' { 'All Media' }
                'filter_media_images' { 'Only Images' }
                'filter_media_videos' { 'Only Videos' }
                'filter_media_audio' { 'Only Audio' }

                'strategy_mod_newest' { 'Newest (Modified)' }
                'strategy_mod_oldest' { 'Oldest (Modified)' }
                'strategy_created_newest' { 'Newest (Created)' }
                'strategy_created_oldest' { 'Oldest (Created)' }
                'strategy_smallest_size' { 'Smallest Size' }
                'strategy_largest_size' { 'Largest Size' }
                'strategy_longest_name' { 'Longest Filename' }
                'strategy_shortest_name' { 'Shortest Filename' }
                'strategy_longest_path' { 'Longest Folder Path' }
                'strategy_shortest_folder_name' { 'Shortest Folder Name' }
                'strategy_deepest_folder' { 'Deepest Folder' }
                'strategy_shallowest_folder' { 'Shallowest Folder' }

                'filter_pick_one_text' { 'Select 1 Per Group' }
                'filter_pick_one_desc' { 'based on strategy' }
                'filter_leave_one_text' { 'Keep 1 Per Group' }
                'filter_leave_one_desc' { 'based on strategy' }
                'filter_swipe_text' { 'Swipe Review' }
                'filter_swipe_desc' { 'left:delete | right:keep' }
                'filter_specific_text' { 'Specific Folder' }
                'filter_specific_desc' { 'duplicates in this folder' }
                'filter_select_all_text' { 'Select All' }
                'filter_deselect_all_text' { 'Clear Selection' }

                'group_header' { 'Group {0}  -  {1} files  -  Recover: {2}' }
                'group_more_files' { '+{0} more files...' }
                'details_template' { 'Size: {0}  |  Type: {1}`nDate: {2}`nFolder: {3}' }
                'unknown_name' { '(Unnamed)' }

                'status_building_list' { 'Building list... {0}/{1}' }
                'status_no_duplicates_in_selected' { 'No duplicates in selected media type' }
                'status_filtering_view' { 'Filtering view...' }
                'status_wait_build_filter' { 'List is building, filter action postponed' }
                'status_wait_build_swipe' { 'List is building, swipe mode postponed' }
                'status_opening_swipe' { 'Opening swipe mode...' }
                'status_swipe_cancelled' { 'Swipe mode cancelled' }
                'status_filter_applying' { 'Applying filter...' }
                'status_thumbnails' { 'Thumbnails {0}/{1}' }

                'status_folder_selected' { '  Folder: {0}' }
                'status_scanning_files' { '  Scanning files...' }
                'status_media_found' { '  {0} media files found.' }
                'status_no_media_found' { '  No media files found.' }
                'status_no_duplicates_found' { '  No duplicates found. ({0} files scanned)' }
                'status_fast_scan' { '  Fast scan... {0}/{1}' }
                'status_full_hash' { '  Full hash... {0}/{1}' }
                'status_scan_summary' { '  {0} groups, {1} files. Recoverable: {2}' }

                'title_info' { 'Info' }
                'title_error' { 'Error' }
                'title_warning' { 'Warning' }
                'title_confirm' { 'Confirm' }
                'title_completed' { 'Completed' }

                'scan_folder_prompt' { 'Select folder to scan' }
                'filter_folder_prompt' { 'Select folder whose duplicates should be selected' }
                'error_invalid_folder' { 'Invalid folder!' }

                'delete_preview_title_default' { 'Swipe' }
                'delete_preview_title_suffix' { '{0} - Files To Delete' }
                'delete_preview_help' { 'Select a file to preview it on the right. Use Del key or REMOVE FROM LIST to remove selected rows.' }
                'delete_preview_col_file' { 'File' }
                'delete_preview_col_size' { 'Size' }
                'delete_preview_col_folder' { 'Folder' }
                'delete_preview_none_selected' { 'No file selected' }
                'delete_preview_remove' { 'REMOVE FROM LIST`n(Del)' }
                'delete_preview_cancel' { 'CANCEL' }
                'delete_preview_approve' { 'APPROVE AND DELETE' }
                'delete_preview_empty' { 'No files left in the delete list.' }
                'delete_preview_source_label' { 'Source' }
                'delete_preview_summary' { '{0} files will be deleted  |  Total: {1}{2}' }

                'delete_confirm_examples_header' { 'Examples from selected files:' }
                'delete_confirm_more_files' { ' - ... +{0} more files' }
                'delete_confirm_source' { 'Source: {0}' }
                'delete_confirm_message' { '{0} files will be deleted ({1}){2}{3}`n`nFiles will be sent to Recycle Bin.`nDo you want to continue?' }
                'delete_status_deleting' { '  Deleting...' }
                'delete_status_error_suffix' { ', {0} errors' }
                'delete_status_done' { '  {0} files sent to Recycle Bin{1}' }
                'delete_done_message' { '{0} / {1} files deleted.' }

                'swipe_need_scan' { 'You need to scan first before starting swipe mode.' }
                'swipe_no_media' { 'No valid media files found for swipe mode.' }
                'swipe_mode_title' { 'Swipe Decision Mode' }
                'swipe_card_progress' { 'Card {0}/{1}' }
                'swipe_counts' { 'Delete: 0  |  Keep: 0' }
                'swipe_counts_full' { 'Delete: {0}  |  Keep: {1}  |  Marked: {2}/{3}' }
                'swipe_decision_waiting' { 'THIS CARD: WAITING FOR DECISION' }
                'swipe_decision_keep' { 'THIS CARD: KEEP' }
                'swipe_decision_delete' { 'THIS CARD: DELETE' }
                'swipe_tag_waiting' { 'Pending' }
                'swipe_tag_keep' { 'KEEP' }
                'swipe_tag_delete' { 'DELETE' }
                'swipe_prev' { 'PREV`n(Backspace)' }
                'swipe_delete' { 'DELETE`n(Left / A)' }
                'swipe_skip' { 'SKIP`n(Space)' }
                'swipe_keep' { 'KEEP`n(Right / D)' }
                'swipe_cancel' { 'CANCEL`n(Esc)' }
                'swipe_finish' { 'FINISH`n(F)' }
                'swipe_early_finish_title' { 'Finish Early' }
                'swipe_early_finish_question' { 'Not all cards are completed. Finish with current decisions?' }
                'swipe_close_confirm' { 'Swipe session is not completed. Exit anyway?' }
                'swipe_finished_early' { 'Swipe finished early' }
                'swipe_finished_done' { 'Swipe completed' }
                'swipe_no_delete_selection' { '{0}. No files were marked for deletion.' }
                'swipe_status_no_delete' { '{0}, no deletion selection' }
                'swipe_status_summary' { '{0}: delete {1}, keep {2}' }
                'swipe_delete_review_source' { 'Swipe mode' }
                'swipe_delete_cancelled' { '{0}, delete cancelled' }
                'swipe_delete_no_remaining' { '{0}, no files left to delete' }
                'swipe_delete_empty_after_review' { 'Delete operation was cancelled because the delete list is empty.' }

                default { $Key }
            }
        }
    }

    if ($text -is [string] -and $text.Contains('`n')) {
        $text = $text.Replace('`n', [Environment]::NewLine)
    }

    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) {
        $resolvedArgs = @($FormatArgs)

        # PowerShell can bind array inputs as a single nested element; flatten one level.
        if ($resolvedArgs.Count -eq 1) {
            $first = $resolvedArgs[0]
            if ($first -is [System.Array]) {
                $resolvedArgs = @($first)
            }
            elseif ($first -is [System.Collections.IList] -and -not ($first -is [string])) {
                $resolvedArgs = @($first)
            }
        }

        try {
            return [string]::Format($text, [object[]]$resolvedArgs)
        }
        catch {
            return $text
        }
    }

    return $text
}

function Get-OneStrategyLabels {
    return @(
        (T 'strategy_mod_newest'),
        (T 'strategy_mod_oldest'),
        (T 'strategy_created_newest'),
        (T 'strategy_created_oldest'),
        (T 'strategy_smallest_size'),
        (T 'strategy_largest_size'),
        (T 'strategy_longest_name'),
        (T 'strategy_shortest_name'),
        (T 'strategy_longest_path'),
        (T 'strategy_shortest_folder_name'),
        (T 'strategy_deepest_folder'),
        (T 'strategy_shallowest_folder')
    )
}

function Get-MediaFilterLabels {
    return @(
        (T 'filter_media_all'),
        (T 'filter_media_images'),
        (T 'filter_media_videos'),
        (T 'filter_media_audio')
    )
}

function Get-FilterButtonText([string]$Tag) {
    switch ($Tag) {
        'pick_one' { return "$(T 'filter_pick_one_text')`n($(T 'filter_pick_one_desc'))" }
        'leave_one' { return "$(T 'filter_leave_one_text')`n($(T 'filter_leave_one_desc'))" }
        'swipe_review' { return "$(T 'filter_swipe_text')`n($(T 'filter_swipe_desc'))" }
        'specific_folder' { return "$(T 'filter_specific_text')`n($(T 'filter_specific_desc'))" }
        'select_all' { return (T 'filter_select_all_text') }
        'deselect_all' { return (T 'filter_deselect_all_text') }
        default { return $Tag }
    }
}

function Get-MediaTypeLabel([string]$MediaType) {
    switch ($MediaType) {
        'image' { return (T 'media_type_image') }
        'video' { return (T 'media_type_video') }
        'audio' { return (T 'media_type_audio') }
        default { return (T 'media_type_other') }
    }
}

function Get-StatusBase([string]$CurrentText) {
    if ([string]::IsNullOrWhiteSpace($CurrentText)) { return '' }

    $base = $CurrentText
    $patterns = @(
        ' \| (Liste hazirlaniyor|Building list).*$',
        ' \| Thumbnails.*$',
        ' \| (Filtre uygulaniyor|Applying filter).*$',
        ' \| (Secili turde kopya yok|No duplicates in selected media type)$',
        ' \| (Gorunum filtreleniyor|Filtering view).*$'
    )

    foreach ($p in $patterns) {
        $base = $base -replace $p, ''
    }

    return $base
}

function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-MediaType([string]$ExtOrPath) {
    $ext = $ExtOrPath
    if (-not $ext) { return "other" }
    if (-not $ext.StartsWith('.')) {
        $ext = [System.IO.Path]::GetExtension($ext)
    }
    $ext = $ext.ToLower()

    if ($script:ImgExt -contains $ext) { return "image" }
    if ($script:VidExt -contains $ext) { return "video" }
    if ($script:AudExt -contains $ext) { return "audio" }
    return "other"
}

function Get-MediaFilterMode {
    $selectedIndex = 0
    if ($script:MediaFilterCombo -and $script:MediaFilterCombo.SelectedIndex -ge 0) {
        $selectedIndex = [int]$script:MediaFilterCombo.SelectedIndex
    }

    switch ($selectedIndex) {
        1 { return "image" }
        2 { return "video" }
        3 { return "audio" }
        default { return "all" }
    }
}

function Test-MediaFilter([string]$ExtOrPath, [string]$Mode) {
    if ($Mode -eq "all") { return $true }
    $tp = Get-MediaType $ExtOrPath
    if ($Mode -eq "image") { return ($tp -eq "image") }
    if ($Mode -eq "video") { return ($tp -eq "video") }
    if ($Mode -eq "audio") { return ($tp -eq "audio") }
    return $true
}

function Set-FilterButtonsEnabled([bool]$HasDuplicateItems) {
    foreach ($b in $filterButtons) {
        if (-not $b) { continue }
        if ([string]$b.Tag -eq "swipe_review") {
            $b.Enabled = ($script:ScannedMediaFiles.Count -gt 0)
        }
        else {
            $b.Enabled = $HasDuplicateItems
        }
    }

    if ($script:OneStrategyCombo) {
        $script:OneStrategyCombo.Enabled = $HasDuplicateItems
    }
}

function Get-MediaViewData([string]$Mode) {
    if (-not $Mode) { $Mode = "all" }
    if ($script:MediaViewCache.ContainsKey($Mode)) {
        return $script:MediaViewCache[$Mode]
    }

    $groups = [System.Collections.ArrayList]::new()
    $hashMeta = @{}
    $gn = 0

    foreach ($hash in $script:Duplicates.Keys) {
        $rawFiles = $script:Duplicates[$hash]
        $files = if ($Mode -eq "all") {
            @($rawFiles)
        } else {
            @($rawFiles | Where-Object { Test-MediaFilter $_.Extension $Mode })
        }
        if ($files.Count -le 1) { continue }

        $gn++

        $newest = $files[0]
        $oldest = $files[0]
        $createdOldest = $files[0]
        $createdNewest = $files[0]
        foreach ($mf in $files) {
            if ($mf.LastWriteTime -gt $newest.LastWriteTime) { $newest = $mf }
            if ($mf.LastWriteTime -lt $oldest.LastWriteTime) { $oldest = $mf }
            if ($mf.CreationTime -lt $createdOldest.CreationTime) { $createdOldest = $mf }
            if ($mf.CreationTime -gt $createdNewest.CreationTime) { $createdNewest = $mf }
        }

        $hashMeta[$hash] = @{
            newest = $newest.FullName
            oldest = $oldest.FullName
            created_oldest = $createdOldest.FullName
            created_newest = $createdNewest.FullName
        }

        $grpWaste = $files[0].Length * ($files.Count - 1)
        $grpHeader = T 'group_header' @($gn, $files.Count, (Format-Size $grpWaste))

        [void]$groups.Add([pscustomobject]@{
            Hash = $hash
            Header = $grpHeader
            Files = $files
        })
    }

    $viewData = [pscustomobject]@{
        HashMeta = $hashMeta
        Groups = $groups
    }
    $script:MediaViewCache[$Mode] = $viewData
    return $viewData
}

function Ensure-ImageIndexCache {
    if ($script:PathToImageIndex.Count -gt 0 -and $imageList.Images.Count -gt 0) { return }

    $script:PathToImageIndex = @{}
    $imageList.Images.Clear()

    foreach ($h in $script:Duplicates.Keys) {
        foreach ($f in $script:Duplicates[$h]) {
            $p = $f.FullName
            if ($script:PathToImageIndex.ContainsKey($p)) { continue }

            $idx = $imageList.Images.Count
            $thumbKey = "$p|${THUMB_W}x${THUMB_H}"
            if ($script:ThumbCache.ContainsKey($thumbKey)) {
                [void]$imageList.Images.Add($script:ThumbCache[$thumbKey])
            } else {
                [void]$imageList.Images.Add($script:PlaceholderThumb.Clone())
            }
            $script:PathToImageIndex[$p] = $idx
        }
    }
}

function Copy-Hashtable([hashtable]$Source) {
    $clone = @{}
    if (-not $Source) { return $clone }
    foreach ($k in $Source.Keys) { $clone[$k] = $Source[$k] }
    return $clone
}

function Save-CurrentModeRenderCache([string]$Mode) {
    if (-not $Mode) { return }

    $itemArray = [System.Windows.Forms.ListViewItem[]]@($lv.Items)
    $groupArray = [System.Windows.Forms.ListViewGroup[]]@($lv.Groups)
    $flatArray = @($script:FlatList)

    $script:ModeRenderCache[$Mode] = [pscustomobject]@{
        Items = $itemArray
        Groups = $groupArray
        FlatList = $flatArray
        PathToHash = Copy-Hashtable $script:PathToHash
        HashMeta = Copy-Hashtable $script:HashMeta
    }
}

function Load-ModeRenderCache([string]$Mode) {
    if (-not $Mode) { return $false }
    if (-not $script:ModeRenderCache.ContainsKey($Mode)) { return $false }

    $cache = $script:ModeRenderCache[$Mode]

    $script:ThumbTimer.Stop()
    $script:BuildTimer.Stop()
    $script:GroupThumbTimer.Stop()
    $script:IsListBuilding = $false
    $script:IsFastViewSwitch = $false
    $script:PendingGroupIndex = -1
    $script:BuildItems = [System.Collections.ArrayList]::new()
    $script:BuildIndex = 0
    $script:UnloadedItems.Clear()

    $lv.BeginUpdate()
    try {
        $lv.Items.Clear()
        $lv.Groups.Clear()

        foreach ($g in $cache.Groups) { [void]$lv.Groups.Add($g) }
        if ($cache.Items.Length -gt 0) { $lv.Items.AddRange($cache.Items) }

        $script:FlatList.Clear()
        foreach ($f in $cache.FlatList) { [void]$script:FlatList.Add($f) }

        $script:PathToHash = Copy-Hashtable $cache.PathToHash
        $script:HashMeta = Copy-Hashtable $cache.HashMeta

        for ($i = 0; $i -lt $script:FlatList.Count; $i++) {
            $f = $script:FlatList[$i]
            if (-not $script:PathToImageIndex.ContainsKey($f.FullName)) { continue }

            $imgIdx = [int]$script:PathToImageIndex[$f.FullName]
            $thumbKey = "$($f.FullName)|${THUMB_W}x${THUMB_H}"
            if (-not $script:ThumbCache.ContainsKey($thumbKey)) {
                [void]$script:UnloadedItems.Add(@{
                    ImageIndex = $imgIdx
                    ItemIndex = $i
                    Path = $f.FullName
                })
            }
        }
    }
    finally {
        $lv.EndUpdate()
    }

    $script:TotalThumbCount = $script:FlatList.Count
    Update-Info

    $hasVisible = ($lv.Items.Count -gt 0)
    Set-FilterButtonsEnabled $hasVisible
    if ($script:MediaFilterCombo) { $script:MediaFilterCombo.Enabled = ($script:Duplicates.Count -gt 0) }

    if ($script:UnloadedItems.Count -gt 0 -and -not $script:ThumbTimer.Enabled) {
        $script:ThumbTimer.Start()
    }

    $lblStatus.Text = $script:PostBuildStatus
    return $true
}

function Get-FastHash([string]$Path, [int]$ByteCount) {
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $buffer = New-Object byte[] ([Math]::Min($ByteCount, $stream.Length))
        [void]$stream.Read($buffer, 0, $buffer.Length)
        $stream.Close(); $stream.Dispose()
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = $md5.ComputeHash($buffer)
        $md5.Dispose()
        return [BitConverter]::ToString($hash).Replace('-','')
    } catch { return $null }
}

function Get-FullHash([string]$Path) {
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = $md5.ComputeHash($stream)
        $stream.Close(); $stream.Dispose(); $md5.Dispose()
        return [BitConverter]::ToString($hash).Replace('-','')
    } catch { return $null }
}

function Make-Thumb([string]$Path, [int]$W, [int]$H) {
    $cacheKey = "${Path}|${W}x${H}"
    $useCache = ($W -eq $THUMB_W -and $H -eq $THUMB_H)
    if ($useCache -and $script:ThumbCache.ContainsKey($cacheKey)) { return $script:ThumbCache[$cacheKey] }
    $fstream = $null
    $srcImg = $null
    try {
        $ext = [System.IO.Path]::GetExtension($Path).ToLower()
        if ($script:VidExt -contains $ext) {
            $videoThumb = $null
            $hBmp = [IntPtr]::Zero
            try {
                $hBmp = [ShellThumbnailProvider]::TryGetThumbnailHBitmap($Path, $W, $H)
                if ($hBmp -ne [IntPtr]::Zero) {
                    $videoThumb = [System.Drawing.Image]::FromHbitmap($hBmp)

                    $thumb = New-Object System.Drawing.Bitmap($W, $H)
                    $g = [System.Drawing.Graphics]::FromImage($thumb)
                    $g.InterpolationMode = 'Bilinear'
                    $g.CompositingQuality = 'HighSpeed'
                    $g.PixelOffsetMode = 'HighSpeed'
                    $g.SmoothingMode = 'HighSpeed'

                    $ratioX = $W / $videoThumb.Width
                    $ratioY = $H / $videoThumb.Height
                    $ratio = [Math]::Min($ratioX, $ratioY)
                    $newW = [int]($videoThumb.Width * $ratio)
                    $newH = [int]($videoThumb.Height * $ratio)
                    $x = [int](($W - $newW) / 2)
                    $y = [int](($H - $newH) / 2)

                    $g.Clear([System.Drawing.Color]::FromArgb(25, 25, 30))
                    $g.DrawImage($videoThumb, $x, $y, $newW, $newH)
                    $g.Dispose()

                    if ($useCache) {
                        if ($script:ThumbCache.Count -gt 3500) { $script:ThumbCache.Clear() }
                        $script:ThumbCache[$cacheKey] = $thumb
                    }
                    return $thumb
                }
            }
            finally {
                try { if ($videoThumb) { $videoThumb.Dispose() } } catch {}
                try {
                    if ($hBmp -ne [IntPtr]::Zero) { [ShellThumbnailProvider]::FreeHBitmap($hBmp) }
                } catch {}
            }

            $bmp = New-Object System.Drawing.Bitmap($W, $H)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.Clear([System.Drawing.Color]::FromArgb(35, 35, 48))
            $g.SmoothingMode = 'AntiAlias'
            $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 255, 255, 255))
            $cx = [int]($W / 2); $cy = [int]($H / 2); $r = [int]([Math]::Min($W,$H) * 0.22)
            $pts = @(
                [System.Drawing.Point]::new($cx - [int]($r*0.6), $cy - $r),
                [System.Drawing.Point]::new($cx - [int]($r*0.6), $cy + $r),
                [System.Drawing.Point]::new($cx + $r, $cy)
            )
            $g.FillPolygon($brush, $pts)
            $fnt = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = 'Center'
            $extBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(100,160,255))
            $g.DrawString($ext.ToUpper().TrimStart('.'), $fnt, $extBrush, [System.Drawing.RectangleF]::new(0, $H-20, $W, 20), $sf)
            $extBrush.Dispose(); $fnt.Dispose(); $brush.Dispose(); $sf.Dispose(); $g.Dispose()
            if ($useCache) {
                if ($script:ThumbCache.Count -gt 3500) { $script:ThumbCache.Clear() }
                $script:ThumbCache[$cacheKey] = $bmp
            }
            return $bmp
        }
        if ($script:AudExt -contains $ext) {
            $bmp = New-Object System.Drawing.Bitmap($W, $H)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.Clear([System.Drawing.Color]::FromArgb(28, 44, 42))
            $g.SmoothingMode = 'AntiAlias'

            $noteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220, 235, 255, 245))
            $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 235, 255, 245), 4)

            $stemX = [int]($W * 0.52)
            $stemTop = [int]($H * 0.20)
            $stemBottom = [int]($H * 0.60)
            $headW = [int]([Math]::Max(16, $W * 0.17))
            $headH = [int]([Math]::Max(12, $H * 0.13))

            $g.DrawLine($linePen, $stemX, $stemTop, $stemX, $stemBottom)
            $g.DrawLine($linePen, $stemX, $stemTop, [int]($stemX + ($W * 0.18)), [int]($stemTop + ($H * 0.06)))
            $g.FillEllipse($noteBrush, [int]($stemX - ($headW * 0.8)), [int]($stemBottom - ($headH * 0.4)), $headW, $headH)
            $g.FillEllipse($noteBrush, [int]($stemX + ($headW * 0.1)), [int]($stemBottom - ($headH * 0.1)), $headW, $headH)

            $fnt = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = 'Center'
            $extBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 220, 190))
            $g.DrawString($ext.ToUpper().TrimStart('.'), $fnt, $extBrush, [System.Drawing.RectangleF]::new(0, $H-20, $W, 20), $sf)

            $extBrush.Dispose(); $fnt.Dispose(); $sf.Dispose(); $linePen.Dispose(); $noteBrush.Dispose(); $g.Dispose()
            if ($useCache) {
                if ($script:ThumbCache.Count -gt 3500) { $script:ThumbCache.Clear() }
                $script:ThumbCache[$cacheKey] = $bmp
            }
            return $bmp
        }
        # Hizli resim yukleme: stream + validation skip
        $fstream = [System.IO.File]::OpenRead($Path)
        $srcImg = [System.Drawing.Image]::FromStream($fstream, $false, $false)
        $thumb = New-Object System.Drawing.Bitmap($W, $H)
        $g = [System.Drawing.Graphics]::FromImage($thumb)
        $g.InterpolationMode = 'Bilinear'
        $g.CompositingQuality = 'HighSpeed'
        $g.PixelOffsetMode = 'HighSpeed'
        $g.SmoothingMode = 'HighSpeed'
        $ratioX = $W / $srcImg.Width
        $ratioY = $H / $srcImg.Height
        $ratio = [Math]::Min($ratioX, $ratioY)
        $newW = [int]($srcImg.Width * $ratio)
        $newH = [int]($srcImg.Height * $ratio)
        $x = [int](($W - $newW) / 2)
        $y = [int](($H - $newH) / 2)
        $g.Clear([System.Drawing.Color]::FromArgb(25, 25, 30))
        $g.DrawImage($srcImg, $x, $y, $newW, $newH)
        $g.Dispose(); $srcImg.Dispose(); $srcImg = $null
        $fstream.Dispose(); $fstream = $null
        if ($useCache) {
            if ($script:ThumbCache.Count -gt 3500) { $script:ThumbCache.Clear() }
            $script:ThumbCache[$cacheKey] = $thumb
        }
        return $thumb
    } catch {
        try { if ($srcImg) { $srcImg.Dispose() } } catch {}
        try { if ($fstream) { $fstream.Dispose() } } catch {}
        $bmp = New-Object System.Drawing.Bitmap($W, $H)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::FromArgb(45, 45, 50))
        $fnt = New-Object System.Drawing.Font("Segoe UI", 8)
        $sf2 = New-Object System.Drawing.StringFormat
        $sf2.Alignment = 'Center'; $sf2.LineAlignment = 'Center'
        $g.DrawString("?", $fnt, [System.Drawing.Brushes]::Gray, [System.Drawing.RectangleF]::new(0,0,$W,$H), $sf2)
        $fnt.Dispose(); $sf2.Dispose(); $g.Dispose()
        if ($useCache) {
            if ($script:ThumbCache.Count -gt 3500) { $script:ThumbCache.Clear() }
            $script:ThumbCache[$cacheKey] = $bmp
        }
        return $bmp
    }
}

# ==================== ANA FORM ====================
$form = New-Object System.Windows.Forms.Form
$form.Text = T 'app_title'
$form.Size = New-Object System.Drawing.Size(1280, 800)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 35)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 650)
$form.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"Instance,NonPublic").SetValue($form, $true, $null)

# ==================== UST PANEL ====================
$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = 'Top'
$topPanel.Height = 56
$topPanel.BackColor = [System.Drawing.Color]::FromArgb(42, 42, 52)
$form.Controls.Add($topPanel)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = T 'app_header'
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(90, 170, 255)
$lblTitle.Location = New-Object System.Drawing.Point(14, 15)
$lblTitle.AutoSize = $true
$topPanel.Controls.Add($lblTitle)

$btnFolder = New-Object System.Windows.Forms.Button
$btnFolder.Text = T 'select_folder'
$btnFolder.Size = New-Object System.Drawing.Size(110, 34)
$btnFolder.Location = New-Object System.Drawing.Point(280, 11)
$btnFolder.FlatStyle = 'Flat'
$btnFolder.BackColor = [System.Drawing.Color]::FromArgb(55, 125, 215)
$btnFolder.ForeColor = [System.Drawing.Color]::White
$btnFolder.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnFolder.FlatAppearance.BorderSize = 0
$btnFolder.Cursor = 'Hand'
$topPanel.Controls.Add($btnFolder)

$chkRecursive = New-Object System.Windows.Forms.CheckBox
$chkRecursive.Text = T 'include_subfolders'
$chkRecursive.ForeColor = [System.Drawing.Color]::LightGray
$chkRecursive.Location = New-Object System.Drawing.Point(400, 17)
$chkRecursive.AutoSize = $true
$chkRecursive.Checked = $true
$topPanel.Controls.Add($chkRecursive)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = T 'scan'
$btnScan.Size = New-Object System.Drawing.Size(90, 34)
$btnScan.Location = New-Object System.Drawing.Point(550, 11)
$btnScan.FlatStyle = 'Flat'
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(45, 170, 75)
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnScan.FlatAppearance.BorderSize = 0
$btnScan.Cursor = 'Hand'
$btnScan.Enabled = $false
$topPanel.Controls.Add($btnScan)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = T 'path_not_selected'
$lblPath.ForeColor = [System.Drawing.Color]::Gray
$lblPath.Location = New-Object System.Drawing.Point(655, 18)
$lblPath.AutoSize = $false
$lblPath.AutoEllipsis = $true
$lblPath.Anchor = 'Top,Left,Right'
$lblPath.Size = New-Object System.Drawing.Size(580, 20)
$topPanel.Controls.Add($lblPath)

$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Text = T 'language'
$lblLang.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 210)
$lblLang.AutoSize = $true
$lblLang.Anchor = 'Top,Right'
$lblLang.Location = New-Object System.Drawing.Point(1130, 5)
$topPanel.Controls.Add($lblLang)

$cmbLanguage = New-Object System.Windows.Forms.ComboBox
$cmbLanguage.DropDownStyle = 'DropDownList'
$cmbLanguage.FlatStyle = 'Flat'
$cmbLanguage.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$cmbLanguage.Size = New-Object System.Drawing.Size(88, 24)
$cmbLanguage.Anchor = 'Top,Right'
$cmbLanguage.Location = New-Object System.Drawing.Point(1128, 23)
[void]$cmbLanguage.Items.AddRange(@('TR', 'EN'))
$cmbLanguage.SelectedIndex = if ($script:CurrentLanguage -eq 'tr') { 0 } else { 1 }
$topPanel.Controls.Add($cmbLanguage)
$script:LanguageCombo = $cmbLanguage
$script:LanguageLabel = $lblLang

# ==================== ALT DURUM ====================
$bottomPanel = New-Object System.Windows.Forms.Panel
$bottomPanel.Dock = 'Bottom'
$bottomPanel.Height = 30
$bottomPanel.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 48)
$form.Controls.Add($bottomPanel)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = T 'status_ready'
$lblStatus.ForeColor = [System.Drawing.Color]::LightGray
$lblStatus.Dock = 'Fill'
$lblStatus.TextAlign = 'MiddleLeft'
$bottomPanel.Controls.Add($lblStatus)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock = 'Bottom'
$progressBar.Height = 3
$progressBar.Style = 'Continuous'
$progressBar.Visible = $false
$form.Controls.Add($progressBar)

$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Dock = 'Fill'
$contentPanel.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 32)
$form.Controls.Add($contentPanel)

# Ana yerlesim: panel cakislarina karsi satir bazli sabit iskelet
$rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rootLayout.Dock = 'Fill'
$rootLayout.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 35)
$rootLayout.ColumnCount = 1
$rootLayout.RowCount = 4
$rootLayout.Margin = New-Object System.Windows.Forms.Padding(0)
$rootLayout.Padding = New-Object System.Windows.Forms.Padding(0)
[void]$rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
[void]$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 3)))
[void]$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
$form.Controls.Add($rootLayout)

$topPanel.Dock = 'Fill'
$contentPanel.Dock = 'Fill'
$progressBar.Dock = 'Fill'
$bottomPanel.Dock = 'Fill'
$topPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$contentPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$progressBar.Margin = New-Object System.Windows.Forms.Padding(0)
$bottomPanel.Margin = New-Object System.Windows.Forms.Padding(0)

[void]$rootLayout.Controls.Add($topPanel, 0, 0)
[void]$rootLayout.Controls.Add($contentPanel, 0, 1)
[void]$rootLayout.Controls.Add($progressBar, 0, 2)
[void]$rootLayout.Controls.Add($bottomPanel, 0, 3)

# ==================== SOL PANEL (FILTRELER) ====================
$leftPanel = New-Object System.Windows.Forms.Panel
$leftPanel.Dock = 'Left'
$leftPanel.Width = 195
$leftPanel.AutoScroll = $true
$leftPanel.BackColor = [System.Drawing.Color]::FromArgb(36, 36, 46)
$contentPanel.Controls.Add($leftPanel)

$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Text = T 'auto_select'
$lblFilter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblFilter.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 80)
$lblFilter.Location = New-Object System.Drawing.Point(10, 8)
$lblFilter.AutoSize = $true
$leftPanel.Controls.Add($lblFilter)

$lblOneStrategy = New-Object System.Windows.Forms.Label
$lblOneStrategy.Text = T 'one_strategy'
$lblOneStrategy.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 190)
$lblOneStrategy.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblOneStrategy.Location = New-Object System.Drawing.Point(10, 30)
$lblOneStrategy.AutoSize = $true
$leftPanel.Controls.Add($lblOneStrategy)

$cmbOneStrategy = New-Object System.Windows.Forms.ComboBox
$cmbOneStrategy.DropDownStyle = 'DropDownList'
$cmbOneStrategy.FlatStyle = 'Flat'
$cmbOneStrategy.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$cmbOneStrategy.Location = New-Object System.Drawing.Point(8, 48)
$cmbOneStrategy.Size = New-Object System.Drawing.Size(178, 24)
$cmbOneStrategy.DropDownWidth = 330
[void]$cmbOneStrategy.Items.AddRange((Get-OneStrategyLabels))
$cmbOneStrategy.SelectedIndex = 0
$cmbOneStrategy.Enabled = $false
$leftPanel.Controls.Add($cmbOneStrategy)
$script:OneStrategyCombo = $cmbOneStrategy

$lblMediaFilter = New-Object System.Windows.Forms.Label
$lblMediaFilter.Text = T 'view_filter'
$lblMediaFilter.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 190)
$lblMediaFilter.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblMediaFilter.Location = New-Object System.Drawing.Point(10, 74)
$lblMediaFilter.AutoSize = $true
$leftPanel.Controls.Add($lblMediaFilter)

$cmbMediaFilter = New-Object System.Windows.Forms.ComboBox
$cmbMediaFilter.DropDownStyle = 'DropDownList'
$cmbMediaFilter.FlatStyle = 'Flat'
$cmbMediaFilter.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$cmbMediaFilter.Location = New-Object System.Drawing.Point(8, 92)
$cmbMediaFilter.Size = New-Object System.Drawing.Size(178, 24)
[void]$cmbMediaFilter.Items.AddRange((Get-MediaFilterLabels))
$cmbMediaFilter.SelectedIndex = 0
$cmbMediaFilter.Enabled = $false
$leftPanel.Controls.Add($cmbMediaFilter)
$script:MediaFilterCombo = $cmbMediaFilter

$filterButtons = @()
$filterDefs = @(
    @{ Tag="pick_one"; C=@(45,145,140) },
    @{ Tag="leave_one"; C=@(45,145,140) },
    @{ Tag="swipe_review"; C=@(45,110,190) },
    @{ Tag="specific_folder"; C=@(120,85,185) },
    @{ Tag="select_all"; C=@(160,125,35) },
    @{ Tag="deselect_all"; C=@(85,85,95) }
)

for ($i = 0; $i -lt $filterDefs.Count; $i++) {
    $d = $filterDefs[$i]
    $btn = New-Object System.Windows.Forms.Button
    $txt = Get-FilterButtonText $d.Tag
    $btn.Text = $txt
    $btn.Size = New-Object System.Drawing.Size(178, 36)
    $yPos = [int](128 + ($i * 40))
    $btn.Location = New-Object System.Drawing.Point(8, $yPos)
    $btn.FlatStyle = 'Flat'
    $btn.BackColor = [System.Drawing.Color]::FromArgb($d.C[0], $d.C[1], $d.C[2])
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = 'Hand'
    $btn.Tag = $d.Tag
    $btn.Enabled = $false
    $btn.TextAlign = 'MiddleCenter'
    $leftPanel.Controls.Add($btn)
    $filterButtons += $btn
}

# Sil butonu
$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = T 'delete_selected_recycle'
$btnDelete.Size = New-Object System.Drawing.Size(178, 44)
$yDel = [int](128 + ($filterDefs.Count * 40) + 10)
$btnDelete.Location = New-Object System.Drawing.Point(8, $yDel)
$btnDelete.FlatStyle = 'Flat'
$btnDelete.BackColor = [System.Drawing.Color]::FromArgb(195, 45, 45)
$btnDelete.ForeColor = [System.Drawing.Color]::White
$btnDelete.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDelete.FlatAppearance.BorderSize = 0
$btnDelete.Cursor = 'Hand'
$btnDelete.Enabled = $false
$leftPanel.Controls.Add($btnDelete)

# Bilgi
$yInfo = [int]($yDel + 52)
$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = T 'selected_count' @(0)
$lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 190)
$lblInfo.Location = New-Object System.Drawing.Point(10, $yInfo)
$lblInfo.AutoSize = $true
$leftPanel.Controls.Add($lblInfo)

$lblInfoSize = New-Object System.Windows.Forms.Label
$lblInfoSize.Text = ""
$lblInfoSize.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 80)
$lblInfoSize.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$yInfoSz = [int]($yInfo + 20)
$lblInfoSize.Location = New-Object System.Drawing.Point(10, $yInfoSz)
$lblInfoSize.AutoSize = $true
$leftPanel.Controls.Add($lblInfoSize)

# ==================== SAG PANEL (ONIZLEME) ====================
$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Dock = 'Right'
$rightPanel.Width = 280
$rightPanel.BackColor = [System.Drawing.Color]::FromArgb(33, 33, 40)
$rightPanel.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
$contentPanel.Controls.Add($rightPanel)

$lblPrv = New-Object System.Windows.Forms.Label
$lblPrv.Text = T 'preview'
$lblPrv.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblPrv.ForeColor = [System.Drawing.Color]::FromArgb(170, 210, 255)
$lblPrv.Dock = 'Top'
$lblPrv.Height = 24
$lblPrv.TextAlign = 'MiddleLeft'
$rightPanel.Controls.Add($lblPrv)

$picPreview = New-Object System.Windows.Forms.PictureBox
$picPreview.Dock = 'Top'
$picPreview.Height = 220
$picPreview.SizeMode = 'Zoom'
$picPreview.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 28)
$picPreview.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
$rightPanel.Controls.Add($picPreview)

$lblFN = New-Object System.Windows.Forms.Label
$lblFN.Text = ""
$lblFN.ForeColor = [System.Drawing.Color]::White
$lblFN.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblFN.Dock = 'Top'
$lblFN.Height = 22
$lblFN.AutoEllipsis = $true
$rightPanel.Controls.Add($lblFN)

$lblFI = New-Object System.Windows.Forms.Label
$lblFI.Text = ""
$lblFI.ForeColor = [System.Drawing.Color]::LightGray
$lblFI.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblFI.Dock = 'Top'
$lblFI.Height = 62
$rightPanel.Controls.Add($lblFI)

# --- Alt kisim: Grup thumbnail + butonlar ---
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = 'Bottom'
$pnlBottom.Height = 34
$pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(33, 33, 40)
$rightPanel.Controls.Add($pnlBottom)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = T 'open_file'
$btnOpen.Dock = 'Left'
$btnOpen.Width = 126
$btnOpen.FlatStyle = 'Flat'
$btnOpen.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 75)
$btnOpen.ForeColor = [System.Drawing.Color]::White
$btnOpen.FlatAppearance.BorderSize = 0
$btnOpen.Cursor = 'Hand'
$pnlBottom.Controls.Add($btnOpen)

$btnOpenDir = New-Object System.Windows.Forms.Button
$btnOpenDir.Text = T 'open_folder'
$btnOpenDir.Dock = 'Right'
$btnOpenDir.Width = 126
$btnOpenDir.FlatStyle = 'Flat'
$btnOpenDir.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 75)
$btnOpenDir.ForeColor = [System.Drawing.Color]::White
$btnOpenDir.FlatAppearance.BorderSize = 0
$btnOpenDir.Cursor = 'Hand'
$pnlBottom.Controls.Add($btnOpenDir)

$lblGrpTitle = New-Object System.Windows.Forms.Label
$lblGrpTitle.Text = T 'group_files'
$lblGrpTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblGrpTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 100)
$lblGrpTitle.Dock = 'Top'
$lblGrpTitle.Height = 22
$lblGrpTitle.TextAlign = 'MiddleLeft'
$rightPanel.Controls.Add($lblGrpTitle)

$grpThumbPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$grpThumbPanel.Dock = 'Fill'
$grpThumbPanel.AutoScroll = $true
$grpThumbPanel.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 35)
$grpThumbPanel.WrapContents = $true
$grpThumbPanel.Padding = New-Object System.Windows.Forms.Padding(4)
$rightPanel.Controls.Add($grpThumbPanel)

# Dock sirasi: Once Fill, sonra Top'lar ters sira eklenmeli
# WinForms Dock: son eklenen once yerlesir. Fill en son eklenmeli
# Sirayi duzelt:
$rightPanel.Controls.Clear()
# Dock Bottom (butonlar) -> en alta
$rightPanel.Controls.Add($pnlBottom)
# Dock Fill (grup thumbs) -> ortaya
$rightPanel.Controls.Add($grpThumbPanel)
# Dock Top (grup baslik) -> grubun ustune
$rightPanel.Controls.Add($lblGrpTitle)
# Dock Top (dosya bilgi)
$rightPanel.Controls.Add($lblFI)
# Dock Top (dosya adi)
$rightPanel.Controls.Add($lblFN)
# Dock Top (resim onizleme)
$rightPanel.Controls.Add($picPreview)
# Dock Top (baslik)
$rightPanel.Controls.Add($lblPrv)

# ==================== ORTA (LISTVIEW) ====================
$imageList = New-Object System.Windows.Forms.ImageList
$imageList.ImageSize = New-Object System.Drawing.Size($THUMB_W, $THUMB_H)
$imageList.ColorDepth = 'Depth32Bit'

$lv = New-Object System.Windows.Forms.ListView
$lv.Dock = 'Fill'
$lv.View = 'LargeIcon'
$lv.LargeImageList = $imageList
$lv.CheckBoxes = $true
$lv.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 32)
$lv.ForeColor = [System.Drawing.Color]::White
$lv.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lv.BorderStyle = 'None'
$lv.FullRowSelect = $true
$lv.MultiSelect = $false
$lv.ShowGroups = $true
$lv.ShowItemToolTips = $true
# Double buffering
$lv.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"Instance,NonPublic").SetValue($lv, $true, $null)

$contentPanel.Controls.Add($lv)

# Icerik panelinde dock sirasini sabitle: Fill alan side barlarin altina girmesin
$contentPanel.Controls.Clear()
$contentPanel.Controls.Add($lv)
$contentPanel.Controls.Add($leftPanel)
$contentPanel.Controls.Add($rightPanel)

$script:UiToolTip = New-Object System.Windows.Forms.ToolTip
$script:UiToolTip.InitialDelay = 250
$script:UiToolTip.ReshowDelay = 120
$script:UiToolTip.AutoPopDelay = 9000

# ==================== VISIBLE-ONLY THUMBNAIL TIMER ====================
$script:ThumbTimer = New-Object System.Windows.Forms.Timer
$script:ThumbTimer.Interval = 50

$script:ThumbTimer.Add_Tick({
    if ($script:UnloadedItems.Count -eq 0) {
        $script:ThumbTimer.Stop()
        $lblStatus.Text = $lblStatus.Text -replace ' \| Thumbnails.*$', ''
        return
    }

    # Sadece gorunen itemlerin thumbnail'ini yukle
    $clientRect = $lv.ClientRectangle
    $loaded = 0
    $toRemove = [System.Collections.ArrayList]::new()

    foreach ($info in $script:UnloadedItems) {
        if ($loaded -ge $script:ThumbsPerTick) { break }
        $itemIdx = $info.ItemIndex
        if ($itemIdx -ge $lv.Items.Count) { [void]$toRemove.Add($info); continue }

        $item = $lv.Items[$itemIdx]
        try {
            $bounds = $item.Bounds
            if ($bounds.Bottom -lt 0 -or $bounds.Top -gt $clientRect.Height) { continue }
            if ($bounds.Right -lt 0 -or $bounds.Left -gt $clientRect.Width) { continue }
        } catch { continue }

        # Bu item gorunuyor ve thumbnail'i henuz yuklenmemis
        $imgIdx = $info.ImageIndex
        $path = $info.Path
        try {
            $thumb = Make-Thumb -Path $path -W $THUMB_W -H $THUMB_H
            if ($thumb -and $imgIdx -lt $imageList.Images.Count) {
                $imageList.Images[$imgIdx] = $thumb
            }
        } catch { }
        [void]$toRemove.Add($info)
        $loaded++
    }

    # Yuklenmisleri listeden cikar
    foreach ($r in $toRemove) { [void]$script:UnloadedItems.Remove($r) }

    if ($loaded -gt 0) {
        $lv.Invalidate()
        $done = $script:TotalThumbCount - $script:UnloadedItems.Count
        $lblStatus.Text = ($lblStatus.Text -replace ' \| Thumbnails.*$', '') + " | $(T 'status_thumbnails' @($done, $script:TotalThumbCount))"
    }
})

$script:BuildTimer = New-Object System.Windows.Forms.Timer
$script:BuildTimer.Interval = 20
$script:BuildTimer.Add_Tick({ Build-ListBatch })

$script:GroupThumbTimer = New-Object System.Windows.Forms.Timer
$script:GroupThumbTimer.Interval = 70
$script:GroupThumbTimer.Add_Tick({
    $script:GroupThumbTimer.Stop()
    $ix = $script:PendingGroupIndex
    if ($ix -ge 0 -and $ix -lt $script:FlatList.Count) {
        Show-GroupThumbs $ix
    }
})

# ==================== FONKSIYONLAR ====================
function Get-OneStrategyKey {
    $idx = 0
    if ($script:OneStrategyCombo -and $script:OneStrategyCombo.SelectedIndex -ge 0) {
        $idx = [int]$script:OneStrategyCombo.SelectedIndex
    }

    if ($idx -lt 0 -or $idx -ge $script:OneStrategyKeys.Count) {
        return 'mod_newest'
    }

    return [string]$script:OneStrategyKeys[$idx]
}

function Apply-Language {
    if ($form) { $form.Text = T 'app_title' }
    if ($lblTitle) { $lblTitle.Text = T 'app_header' }
    if ($btnFolder) { $btnFolder.Text = T 'select_folder' }
    if ($chkRecursive) { $chkRecursive.Text = T 'include_subfolders' }
    if ($btnScan) { $btnScan.Text = T 'scan' }

    if ($script:LanguageLabel) {
        $script:LanguageLabel.Text = T 'language'
    }

    if ($script:LanguageCombo) {
        $langIndex = if ($script:CurrentLanguage -eq 'tr') { 0 } else { 1 }
        if ($script:LanguageCombo.SelectedIndex -ne $langIndex) {
            $script:LanguageCombo.SelectedIndex = $langIndex
        }
    }

    if ($lblFilter) { $lblFilter.Text = T 'auto_select' }
    if ($lblOneStrategy) { $lblOneStrategy.Text = T 'one_strategy' }
    if ($lblMediaFilter) { $lblMediaFilter.Text = T 'view_filter' }
    if ($btnDelete) { $btnDelete.Text = T 'delete_selected_recycle' }

    if ($lblPrv) { $lblPrv.Text = T 'preview' }
    if ($btnOpen) { $btnOpen.Text = T 'open_file' }
    if ($btnOpenDir) { $btnOpenDir.Text = T 'open_folder' }
    if ($lblGrpTitle) { $lblGrpTitle.Text = T 'group_files' }

    if ($script:OneStrategyCombo) {
        $idx = $script:OneStrategyCombo.SelectedIndex
        if ($idx -lt 0) { $idx = 0 }
        $script:OneStrategyCombo.Items.Clear()
        [void]$script:OneStrategyCombo.Items.AddRange((Get-OneStrategyLabels))
        if ($idx -ge $script:OneStrategyCombo.Items.Count) { $idx = 0 }
        if ($script:OneStrategyCombo.Items.Count -gt 0) {
            $script:OneStrategyCombo.SelectedIndex = $idx
        }
    }

    if ($script:MediaFilterCombo) {
        $idx = $script:MediaFilterCombo.SelectedIndex
        if ($idx -lt 0) { $idx = 0 }
        $script:MediaFilterCombo.Items.Clear()
        [void]$script:MediaFilterCombo.Items.AddRange((Get-MediaFilterLabels))
        if ($idx -ge $script:MediaFilterCombo.Items.Count) { $idx = 0 }
        if ($script:MediaFilterCombo.Items.Count -gt 0) {
            $script:MediaFilterCombo.SelectedIndex = $idx
        }
    }

    foreach ($b in $filterButtons) {
        if (-not $b) { continue }
        $b.Text = Get-FilterButtonText ([string]$b.Tag)
    }

    if ([string]::IsNullOrWhiteSpace($script:SelectedFolderPath)) {
        $lblPath.Text = T 'path_not_selected'
        $lblPath.ForeColor = [System.Drawing.Color]::Gray
    }
    else {
        $lblPath.Text = $script:SelectedFolderPath
        $lblPath.ForeColor = [System.Drawing.Color]::FromArgb(140, 210, 255)
    }

    if ([string]::IsNullOrWhiteSpace($script:SelectedFolderPath) -and $script:Duplicates.Count -eq 0 -and -not $script:IsListBuilding) {
        $lblStatus.Text = T 'status_ready'
    }

    Update-Info
}

function Update-Info {
    $checked = @($lv.CheckedItems)
    $cnt = $checked.Count
    $sz = [long]0
    foreach ($ci in $checked) {
        $ix = [int]$ci.Tag
        if ($ix -ge 0 -and $ix -lt $script:FlatList.Count) { $sz += $script:FlatList[$ix].Length }
    }
    $lblInfo.Text = T 'selected_count' @($cnt)
    $lblInfoSize.Text = if ($cnt -gt 0) { T 'selected_size' @((Format-Size $sz)) } else { "" }
    $btnDelete.Enabled = ($cnt -gt 0)
}

function Apply-ResponsiveLayout {
    $w = $form.ClientSize.Width
    if ($w -le 0) { return }

    if ($w -lt 1120) {
        $leftPanel.Width = 165
        $rightPanel.Width = 220
        $picPreview.Height = 165
        $lblFI.Height = 72
        $script:BuildBatchSize = 95
        $script:ThumbsPerTick = 3
        $script:ThumbTimer.Interval = 65
        $script:MaxGroupThumbItems = 20
    }
    elseif ($w -lt 1400) {
        $leftPanel.Width = 180
        $rightPanel.Width = 250
        $picPreview.Height = 195
        $lblFI.Height = 66
        $script:BuildBatchSize = 120
        $script:ThumbsPerTick = 4
        $script:ThumbTimer.Interval = 55
        $script:MaxGroupThumbItems = 28
    }
    else {
        $leftPanel.Width = 195
        $rightPanel.Width = 280
        $picPreview.Height = 220
        $lblFI.Height = 62
        $script:BuildBatchSize = 150
        $script:ThumbsPerTick = 5
        $script:ThumbTimer.Interval = 45
        $script:MaxGroupThumbItems = 36
    }

    $btnW = [Math]::Max(140, $leftPanel.Width - 16)
    foreach ($b in $filterButtons) { $b.Width = $btnW }
    $btnDelete.Width = $btnW
    if ($script:OneStrategyCombo) { $script:OneStrategyCombo.Width = $btnW }
    if ($script:MediaFilterCombo) { $script:MediaFilterCombo.Width = $btnW }

    $maxLabelW = [Math]::Max(120, $leftPanel.Width - 16)
    $lblInfo.MaximumSize = New-Object System.Drawing.Size($maxLabelW, 0)
    $lblInfoSize.MaximumSize = New-Object System.Drawing.Size($maxLabelW, 0)

    if ($script:LanguageCombo -and $script:LanguageLabel) {
        $script:LanguageCombo.Width = 74
        $comboW = [Math]::Max(66, $script:LanguageCombo.Width)
        $comboX = [Math]::Max(0, $topPanel.ClientSize.Width - $comboW - 12)
        $comboY = 16
        $script:LanguageCombo.Location = New-Object System.Drawing.Point($comboX, $comboY)

        $langW = [System.Windows.Forms.TextRenderer]::MeasureText($script:LanguageLabel.Text, $script:LanguageLabel.Font).Width
        $langW = [Math]::Max(24, $langW)
        $labelX = [Math]::Max(0, $comboX - $langW - 8)

        $pathRight = $labelX - 12
        $pathW = $pathRight - $lblPath.Left

        if ($pathW -lt 140) {
            $script:LanguageLabel.Visible = $false
            $pathRight = $comboX - 8
            $pathW = $pathRight - $lblPath.Left
        }
        else {
            $script:LanguageLabel.Visible = $true
            $script:LanguageLabel.Location = New-Object System.Drawing.Point($labelX, ($comboY + 4))
        }

        $pathW = [Math]::Max(100, $pathW)
        $lblPath.Size = New-Object System.Drawing.Size($pathW, $lblPath.Height)
    }
}

function Show-GroupThumbs([int]$FileIndex) {
    if ($FileIndex -lt 0 -or $FileIndex -ge $script:FlatList.Count) { return }

    $grpThumbPanel.SuspendLayout()
    try {
        # Eski kontrolleri temizle
        foreach ($c in @($grpThumbPanel.Controls)) {
            $grpThumbPanel.Controls.Remove($c)
            $c.Dispose()
        }

        $targetFile = $script:FlatList[$FileIndex]
        if (-not $script:PathToHash.ContainsKey($targetFile.FullName)) { return }

        $hash = $script:PathToHash[$targetFile.FullName]
        if (-not $script:Duplicates.ContainsKey($hash)) { return }

        $grp = $script:Duplicates[$hash]
        if ($grp.Count -eq 0) { return }

        # Cok buyuk gruplarda paneli kilitlememek icin sinirli sayida thumb goster
        $display = [System.Collections.ArrayList]::new()
        [void]$display.Add($targetFile)
        foreach ($f in $grp) {
            if ($f.FullName -eq $targetFile.FullName) { continue }
            [void]$display.Add($f)
            if ($display.Count -ge $script:MaxGroupThumbItems) { break }
        }

        foreach ($f in $display) {
            $panel = New-Object System.Windows.Forms.Panel
            $panel.Size = New-Object System.Drawing.Size(88, 94)
            $panel.Margin = New-Object System.Windows.Forms.Padding(2)
            if ($f.FullName -eq $targetFile.FullName) {
                $panel.BackColor = [System.Drawing.Color]::FromArgb(50, 100, 200)
            } else {
                $panel.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 50)
            }

            $pic = New-Object System.Windows.Forms.PictureBox
            $pic.Size = New-Object System.Drawing.Size(84, 60)
            $pic.Location = New-Object System.Drawing.Point(2, 2)
            $pic.SizeMode = 'Zoom'
            $pic.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 38)
            $ck = "$($f.FullName)|${THUMB_W}x${THUMB_H}"
            if ($script:ThumbCache.ContainsKey($ck)) {
                $pic.Image = $script:ThumbCache[$ck]
            }
            $panel.Controls.Add($pic)

            $lbl = New-Object System.Windows.Forms.Label
            $lbl.Text = $f.Name
            $lbl.ForeColor = [System.Drawing.Color]::LightGray
            $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 6.5)
            $lbl.Location = New-Object System.Drawing.Point(2, 64)
            $lbl.Size = New-Object System.Drawing.Size(84, 28)
            $lbl.AutoEllipsis = $true
            $panel.Controls.Add($lbl)

            if ($script:UiToolTip) {
                $script:UiToolTip.SetToolTip($panel, $f.FullName)
                $script:UiToolTip.SetToolTip($pic, $f.FullName)
                $script:UiToolTip.SetToolTip($lbl, $f.FullName)
            }

            $grpThumbPanel.Controls.Add($panel)
        }

        if ($grp.Count -gt $display.Count) {
            $more = $grp.Count - $display.Count
            $moreLbl = New-Object System.Windows.Forms.Label
            $moreLbl.Text = T 'group_more_files' @($more)
            $moreLbl.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 210)
            $moreLbl.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
            $moreLbl.AutoSize = $true
            $moreLbl.Margin = New-Object System.Windows.Forms.Padding(8, 10, 4, 4)
            $grpThumbPanel.Controls.Add($moreLbl)
        }
    }
    finally {
        $grpThumbPanel.ResumeLayout()
    }
}

function Build-ListBatch {
    if (-not $script:IsListBuilding) { return }
    if ($script:BuildIndex -ge $script:BuildItems.Count) {
        $script:BuildTimer.Stop()
        $script:IsListBuilding = $false
        Save-CurrentModeRenderCache $script:CurrentMediaMode
        $script:IsFastViewSwitch = $false
        $lblStatus.Text = $script:PostBuildStatus
        $hasVisible = ($lv.Items.Count -gt 0)
        Set-FilterButtonsEnabled $hasVisible
        if ($script:MediaFilterCombo) { $script:MediaFilterCombo.Enabled = ($script:Duplicates.Count -gt 0) }
        Update-Info
        if ($script:UnloadedItems.Count -gt 0 -and -not $script:ThumbTimer.Enabled) {
            $script:ThumbTimer.Start()
        }
        return
    }

    $processed = 0
    $lv.BeginUpdate()
    try {
        $itemsToAdd = New-Object 'System.Collections.Generic.List[System.Windows.Forms.ListViewItem]'
        $baseItemIndex = $lv.Items.Count
        while ($script:BuildIndex -lt $script:BuildItems.Count -and $processed -lt $script:ActiveBuildBatchSize) {
            $entry = $script:BuildItems[$script:BuildIndex]
            $f = $entry.File

            $fi = $script:FlatList.Count
            [void]$script:FlatList.Add($f)
            $script:PathToHash[$f.FullName] = $entry.Hash

            if (-not $script:PathToImageIndex.ContainsKey($f.FullName)) {
                $imgIdxNew = $imageList.Images.Count
                [void]$imageList.Images.Add($script:PlaceholderThumb.Clone())
                $script:PathToImageIndex[$f.FullName] = $imgIdxNew
            }

            $imgIdx = [int]$script:PathToImageIndex[$f.FullName]
            $thumbKey = "$($f.FullName)|${THUMB_W}x${THUMB_H}"
            $hasCachedThumb = $script:ThumbCache.ContainsKey($thumbKey)
            $itemIdx = $baseItemIndex + $itemsToAdd.Count

            if (-not $hasCachedThumb) {
                [void]$script:UnloadedItems.Add(@{
                    ImageIndex = $imgIdx
                    ItemIndex = $itemIdx
                    Path = $f.FullName
                })
            }

            $ext = $f.Extension.ToLower()
            $tp = Get-MediaType $ext
            $tpLabel = Get-MediaTypeLabel $tp
            $label = "$($f.Name)`n$(Format-Size $f.Length)"

            $item = New-Object System.Windows.Forms.ListViewItem($label, $imgIdx)
            [void]$item.SubItems.Add($f.DirectoryName)
            [void]$item.SubItems.Add("$(Format-Size $f.Length)  |  $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))  |  $tpLabel")
            $item.Tag = $fi
            $item.Group = $entry.Group
            $item.ToolTipText = $f.FullName
            if ($entry.IsFirst) {
                $item.ForeColor = [System.Drawing.Color]::FromArgb(90, 210, 120)
            }
            [void]$itemsToAdd.Add($item)

            $script:BuildIndex++
            $processed++
        }

        if ($itemsToAdd.Count -gt 0) {
            $lv.Items.AddRange($itemsToAdd.ToArray())
        }
    }
    finally {
        $lv.EndUpdate()
    }

    if (-not $script:IsFastViewSwitch) {
        $lblStatus.Text = "$($script:PostBuildStatus) | $(T 'status_building_list' @($script:BuildIndex, $script:BuildItems.Count))"
    }
}

function Fill-List([switch]$FastViewSwitch) {
    $script:ThumbTimer.Stop()
    $script:BuildTimer.Stop()
    $script:GroupThumbTimer.Stop()
    $script:IsListBuilding = $false
    $script:IsFastViewSwitch = $FastViewSwitch.IsPresent
    $script:PendingGroupIndex = -1

    $script:PostBuildStatus = Get-StatusBase $lblStatus.Text

    $mediaMode = Get-MediaFilterMode
    $script:CurrentMediaMode = $mediaMode

    if (-not $script:PlaceholderThumb) {
        $script:PlaceholderThumb = New-Object System.Drawing.Bitmap($THUMB_W, $THUMB_H)
        $pg = [System.Drawing.Graphics]::FromImage($script:PlaceholderThumb)
        $pg.Clear([System.Drawing.Color]::FromArgb(38, 38, 46))
        $dotBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 80, 90))
        $dotFont = New-Object System.Drawing.Font("Segoe UI", 10)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $pg.DrawString("...", $dotFont, $dotBrush, [System.Drawing.RectangleF]::new(0,0,$THUMB_W,$THUMB_H), $sf)
        $dotBrush.Dispose(); $dotFont.Dispose(); $sf.Dispose(); $pg.Dispose()
    }

    Ensure-ImageIndexCache

    if (Load-ModeRenderCache $mediaMode) {
        return
    }

    $script:UnloadedItems.Clear()
    $lv.Items.Clear()
    $lv.Groups.Clear()
    $script:FlatList.Clear()
    $script:PathToHash = @{}
    $script:HashMeta = @{}
    $script:BuildItems = [System.Collections.ArrayList]::new()
    $script:BuildIndex = 0

    Set-FilterButtonsEnabled $false
    if ($script:MediaFilterCombo) { $script:MediaFilterCombo.Enabled = $false }
    $btnDelete.Enabled = $false

    $viewData = Get-MediaViewData $mediaMode
    $script:HashMeta = $viewData.HashMeta

    $gn = 0

    foreach ($g in $viewData.Groups) {
        $gn++
        $hash = $g.Hash
        $files = $g.Files

        # GRUP BASLIGI
        $lvGroup = New-Object System.Windows.Forms.ListViewGroup("grp_$gn", $g.Header)
        $lvGroup.HeaderAlignment = 'Left'
        [void]$lv.Groups.Add($lvGroup)

        $first = $true
        foreach ($f in $files) {
            [void]$script:BuildItems.Add([pscustomobject]@{
                File = $f
                Hash = $hash
                Group = $lvGroup
                IsFirst = $first
            })
            if ($first) { $first = $false }
        }
    }

    $script:TotalThumbCount = $script:BuildItems.Count
    Update-Info
    if ($script:BuildItems.Count -eq 0) {
        $script:IsFastViewSwitch = $false
        $lblStatus.Text = "$($script:PostBuildStatus) | $(T 'status_no_duplicates_in_selected')"
        Set-FilterButtonsEnabled $false
        if ($script:MediaFilterCombo) { $script:MediaFilterCombo.Enabled = ($script:Duplicates.Count -gt 0) }
        return
    }

    $script:IsListBuilding = $true
    if ($FastViewSwitch) {
        $script:ActiveBuildBatchSize = [Math]::Max(260, $script:BuildBatchSize * 3)
        $script:BuildTimer.Interval = 8
        $lblStatus.Text = "$($script:PostBuildStatus) | $(T 'status_filtering_view')"
        $script:BuildTimer.Start()
    }
    else {
        $script:ActiveBuildBatchSize = $script:BuildBatchSize
        $script:BuildTimer.Interval = 20
        $lblStatus.Text = "$($script:PostBuildStatus) | $(T 'status_building_list' @(0, $script:BuildItems.Count))"
        $script:BuildTimer.Start()
    }
}

function Get-DirectoryDepth([string]$DirectoryPath) {
    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) { return 0 }

    $p = $DirectoryPath.TrimEnd('\\','/')
    if ([string]::IsNullOrWhiteSpace($p)) { return 0 }

    $root = [System.IO.Path]::GetPathRoot($p)
    $rest = $p
    if ($root -and $p.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rest = $p.Substring($root.Length)
    }

    if ([string]::IsNullOrWhiteSpace($rest)) { return 0 }
    $parts = @($rest -split '[\\/]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return $parts.Count
}

function Get-LeafFolderNameLength([string]$DirectoryPath) {
    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) { return 0 }
    $trimmed = $DirectoryPath.TrimEnd('\\','/')
    $leaf = [System.IO.Path]::GetFileName($trimmed)
    if ([string]::IsNullOrWhiteSpace($leaf)) { return 0 }
    return $leaf.Length
}

function Get-PreferredPathByScore([object[]]$Files, [scriptblock]$Score, [switch]$PreferHigher) {
    $arr = @($Files)
    if ($arr.Count -eq 0) { return $null }

    $best = $arr[0]
    $bestScore = & $Score $best

    for ($i = 1; $i -lt $arr.Count; $i++) {
        $cand = $arr[$i]
        $candScore = & $Score $cand

        $isBetter = if ($PreferHigher.IsPresent) { $candScore -gt $bestScore } else { $candScore -lt $bestScore }
        if ($isBetter) {
            $best = $cand
            $bestScore = $candScore
            continue
        }

        if ($candScore -eq $bestScore) {
            if ([string]::Compare($cand.FullName, $best.FullName, $true) -lt 0) {
                $best = $cand
                $bestScore = $candScore
            }
        }
    }

    return $best.FullName
}

function Get-OneStrategyKeepPath([hashtable]$meta, [object[]]$files) {
    $files = @($files)
    if ($files.Count -eq 0) { return $null }
    if (-not $meta) { $meta = @{} }

    $choice = Get-OneStrategyKey

    switch ($choice) {
        "mod_oldest" {
            if ($meta.ContainsKey("oldest") -and $meta["oldest"]) { return $meta["oldest"] }
            return Get-PreferredPathByScore -Files $files -Score { param($f) [long]$f.LastWriteTimeUtc.Ticks }
        }
        "created_newest" {
            if ($meta.ContainsKey("created_newest") -and $meta["created_newest"]) { return $meta["created_newest"] }
            return Get-PreferredPathByScore -Files $files -Score { param($f) [long]$f.CreationTimeUtc.Ticks } -PreferHigher
        }
        "created_oldest" {
            if ($meta.ContainsKey("created_oldest") -and $meta["created_oldest"]) { return $meta["created_oldest"] }
            return Get-PreferredPathByScore -Files $files -Score { param($f) [long]$f.CreationTimeUtc.Ticks }
        }
        "smallest_size" {
            return Get-PreferredPathByScore -Files $files -Score { param($f) [long]$f.Length }
        }
        "largest_size" {
            return Get-PreferredPathByScore -Files $files -Score { param($f) [long]$f.Length } -PreferHigher
        }
        "longest_name" {
            return Get-PreferredPathByScore -Files $files -Score { param($f) [int]$f.Name.Length } -PreferHigher
        }
        "shortest_name" {
            return Get-PreferredPathByScore -Files $files -Score { param($f) [int]$f.Name.Length }
        }
        "longest_path" {
            return Get-PreferredPathByScore -Files $files -Score { param($f) [int]$f.DirectoryName.Length } -PreferHigher
        }
        "shortest_folder_name" {
            return Get-PreferredPathByScore -Files $files -Score { param($f) [int](Get-LeafFolderNameLength $f.DirectoryName) }
        }
        "deepest_folder" {
            return Get-PreferredPathByScore -Files $files -Score { param($f) [int](Get-DirectoryDepth $f.DirectoryName) } -PreferHigher
        }
        "shallowest_folder" {
            return Get-PreferredPathByScore -Files $files -Score { param($f) [int](Get-DirectoryDepth $f.DirectoryName) }
        }
        default {
            if ($meta.ContainsKey("newest") -and $meta["newest"]) { return $meta["newest"] }
            return Get-PreferredPathByScore -Files $files -Score { param($f) [long]$f.LastWriteTimeUtc.Ticks } -PreferHigher
        }
    }
}

function Ensure-RecycleBinType {
    if ("RecycleBin" -as [type]) { return }

    Add-Type @"
using System;
using System.Runtime.InteropServices;

public class RecycleBin {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string pTo;
        public ushort fFlags;
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT FileOp);

    private const uint FO_DELETE = 0x03;
    private const ushort FOF_ALLOWUNDO = 0x40;
    private const ushort FOF_NOCONFIRMATION = 0x10;
    private const ushort FOF_SILENT = 0x04;

    public static int SendToRecycleBin(string path) {
        var fs = new SHFILEOPSTRUCT();
        fs.wFunc = FO_DELETE;
        fs.pFrom = path + '\0' + '\0';
        fs.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT;
        return SHFileOperation(ref fs);
    }
}
"@ -ErrorAction SilentlyContinue
}

function Remove-FromScannedMediaFiles([string[]]$DeletedPaths) {
    $arr = @($DeletedPaths)
    if ($arr.Count -eq 0) { return }

    $pathSet = @{}
    foreach ($p in $arr) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $pathSet[$p] = $true
    }

    $newFiles = [System.Collections.ArrayList]::new()
    foreach ($f in @($script:ScannedMediaFiles)) {
        if (-not $f) { continue }
        $fp = $f.FullName
        if ([string]::IsNullOrWhiteSpace($fp)) { continue }
        if ($pathSet.ContainsKey($fp)) { continue }
        [void]$newFiles.Add($f)
    }

    $script:ScannedMediaFiles = $newFiles
}

function Show-DeletePreviewDialog([object[]]$FilesToDelete, [string]$Title, [string]$SourceLabel) {
    $result = [pscustomobject]@{
        Approved = $false
        Files = @()
    }

    $targets = [System.Collections.ArrayList]::new()
    $seen = @{}

    foreach ($f in @($FilesToDelete)) {
        if (-not $f) { continue }
        $p = $f.FullName
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($seen.ContainsKey($p)) { continue }
        $seen[$p] = $true
        [void]$targets.Add($f)
    }

    if ($targets.Count -eq 0) { return $result }

    $workingTargets = [System.Collections.ArrayList]::new()
    foreach ($f in $targets) { [void]$workingTargets.Add($f) }

    $dlg = New-Object System.Windows.Forms.Form
    $dlgTitleBase = if ([string]::IsNullOrWhiteSpace($Title)) { T 'delete_preview_title_default' } else { $Title }
    $dlg.Text = T 'delete_preview_title_suffix' @($dlgTitleBase)
    $dlg.Size = New-Object System.Drawing.Size(1080, 650)
    $dlg.MinimumSize = New-Object System.Drawing.Size(840, 520)
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 30)
    $dlg.ForeColor = [System.Drawing.Color]::White
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $dlg.KeyPreview = $true

    $pCenter = New-Object System.Windows.Forms.Panel
    $pCenter.Dock = 'Fill'
    $dlg.Controls.Add($pCenter)

    $pTop = New-Object System.Windows.Forms.Panel
    $pTop.Dock = 'Top'
    $pTop.Height = 68
    $pTop.BackColor = [System.Drawing.Color]::FromArgb(34, 34, 44)
    $dlg.Controls.Add($pTop)

    $pBottom = New-Object System.Windows.Forms.Panel
    $pBottom.Dock = 'Bottom'
    $pBottom.Height = 82
    $pBottom.BackColor = [System.Drawing.Color]::FromArgb(34, 34, 44)
    $dlg.Controls.Add($pBottom)

    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(14, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(1030, 22)
    $lblSummary.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lblSummary.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $pTop.Controls.Add($lblSummary)

    $lblHelp = New-Object System.Windows.Forms.Label
    $lblHelp.Text = T 'delete_preview_help'
    $lblHelp.Location = New-Object System.Drawing.Point(14, 35)
    $lblHelp.Size = New-Object System.Drawing.Size(1030, 22)
    $lblHelp.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 190)
    $pTop.Controls.Add($lblHelp)

    $splitDeletePreview = New-Object System.Windows.Forms.SplitContainer
    $splitDeletePreview.Dock = 'Fill'
    $splitDeletePreview.Orientation = 'Vertical'
    $splitDeletePreview.SplitterWidth = 6
    $splitDeletePreview.Panel1MinSize = 430
    $pCenter.Controls.Add($splitDeletePreview)

    $lvDeletePreview = New-Object System.Windows.Forms.ListView
    $lvDeletePreview.Dock = 'Fill'
    $lvDeletePreview.View = 'Details'
    $lvDeletePreview.FullRowSelect = $true
    $lvDeletePreview.GridLines = $true
    $lvDeletePreview.HideSelection = $false
    $lvDeletePreview.MultiSelect = $true
    $lvDeletePreview.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 28)
    $lvDeletePreview.ForeColor = [System.Drawing.Color]::White
    [void]$lvDeletePreview.Columns.Add((T 'delete_preview_col_file'), 260)
    [void]$lvDeletePreview.Columns.Add((T 'delete_preview_col_size'), 110)
    [void]$lvDeletePreview.Columns.Add((T 'delete_preview_col_folder'), 520)
    $splitDeletePreview.Panel1.Controls.Add($lvDeletePreview)

    $pPreview = New-Object System.Windows.Forms.Panel
    $pPreview.Dock = 'Fill'
    $pPreview.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 28)
    $splitDeletePreview.Panel2.Controls.Add($pPreview)

    $pPreviewTop = New-Object System.Windows.Forms.Panel
    $pPreviewTop.Dock = 'Top'
    $pPreviewTop.Height = 32
    $pPreviewTop.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 38)
    $pPreview.Controls.Add($pPreviewTop)

    $lblPreviewTitle = New-Object System.Windows.Forms.Label
    $lblPreviewTitle.Text = T 'preview'
    $lblPreviewTitle.Location = New-Object System.Drawing.Point(10, 7)
    $lblPreviewTitle.Size = New-Object System.Drawing.Size(220, 18)
    $lblPreviewTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $pPreviewTop.Controls.Add($lblPreviewTitle)

    $pPreviewBottom = New-Object System.Windows.Forms.Panel
    $pPreviewBottom.Dock = 'Bottom'
    $pPreviewBottom.Height = 84
    $pPreviewBottom.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 38)
    $pPreview.Controls.Add($pPreviewBottom)

    $lblPreviewInfo1 = New-Object System.Windows.Forms.Label
    $lblPreviewInfo1.Text = T 'delete_preview_none_selected'
    $lblPreviewInfo1.Location = New-Object System.Drawing.Point(10, 8)
    $lblPreviewInfo1.Size = New-Object System.Drawing.Size(350, 18)
    $lblPreviewInfo1.AutoEllipsis = $true
    $lblPreviewInfo1.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $pPreviewBottom.Controls.Add($lblPreviewInfo1)

    $lblPreviewInfo2 = New-Object System.Windows.Forms.Label
    $lblPreviewInfo2.Text = ""
    $lblPreviewInfo2.Location = New-Object System.Drawing.Point(10, 30)
    $lblPreviewInfo2.Size = New-Object System.Drawing.Size(350, 18)
    $lblPreviewInfo2.AutoEllipsis = $true
    $lblPreviewInfo2.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $pPreviewBottom.Controls.Add($lblPreviewInfo2)

    $lblPreviewInfo3 = New-Object System.Windows.Forms.Label
    $lblPreviewInfo3.Text = ""
    $lblPreviewInfo3.Location = New-Object System.Drawing.Point(10, 52)
    $lblPreviewInfo3.Size = New-Object System.Drawing.Size(350, 18)
    $lblPreviewInfo3.AutoEllipsis = $true
    $lblPreviewInfo3.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $pPreviewBottom.Controls.Add($lblPreviewInfo3)

    $picDeletePreview = New-Object System.Windows.Forms.PictureBox
    $picDeletePreview.Dock = 'Fill'
    $picDeletePreview.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 22)
    $picDeletePreview.SizeMode = 'Zoom'
    $pPreview.Controls.Add($picDeletePreview)

    $btnRemoveFromDeleteList = New-Object System.Windows.Forms.Button
    $btnRemoveFromDeleteList.Text = T 'delete_preview_remove'
    $btnRemoveFromDeleteList.Size = New-Object System.Drawing.Size(170, 48)
    $btnRemoveFromDeleteList.FlatStyle = 'Flat'
    $btnRemoveFromDeleteList.FlatAppearance.BorderSize = 0
    $btnRemoveFromDeleteList.BackColor = [System.Drawing.Color]::FromArgb(118, 96, 44)
    $btnRemoveFromDeleteList.ForeColor = [System.Drawing.Color]::White
    $btnRemoveFromDeleteList.Cursor = 'Hand'
    $pBottom.Controls.Add($btnRemoveFromDeleteList)

    $btnCancelDeletePreview = New-Object System.Windows.Forms.Button
    $btnCancelDeletePreview.Text = T 'delete_preview_cancel'
    $btnCancelDeletePreview.Size = New-Object System.Drawing.Size(140, 48)
    $btnCancelDeletePreview.FlatStyle = 'Flat'
    $btnCancelDeletePreview.FlatAppearance.BorderSize = 0
    $btnCancelDeletePreview.BackColor = [System.Drawing.Color]::FromArgb(90, 90, 102)
    $btnCancelDeletePreview.ForeColor = [System.Drawing.Color]::White
    $btnCancelDeletePreview.Cursor = 'Hand'
    $pBottom.Controls.Add($btnCancelDeletePreview)

    $btnApproveDeletePreview = New-Object System.Windows.Forms.Button
    $btnApproveDeletePreview.Text = T 'delete_preview_approve'
    $btnApproveDeletePreview.Size = New-Object System.Drawing.Size(190, 48)
    $btnApproveDeletePreview.FlatStyle = 'Flat'
    $btnApproveDeletePreview.FlatAppearance.BorderSize = 0
    $btnApproveDeletePreview.BackColor = [System.Drawing.Color]::FromArgb(195, 55, 55)
    $btnApproveDeletePreview.ForeColor = [System.Drawing.Color]::White
    $btnApproveDeletePreview.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
    $btnApproveDeletePreview.Cursor = 'Hand'
    $pBottom.Controls.Add($btnApproveDeletePreview)

    $layoutDeletePreviewButtons = {
        $margin = 14
        $gap = 10
        $y = 17

        $removeW = $btnRemoveFromDeleteList.Width
        $cancelW = $btnCancelDeletePreview.Width
        $approveW = $btnApproveDeletePreview.Width

        $btnRemoveFromDeleteList.Location = New-Object System.Drawing.Point($margin, $y)

        $xApprove = $pBottom.ClientSize.Width - $margin - $approveW
        if ($xApprove -lt ($margin + $removeW + $gap)) { $xApprove = $margin + $removeW + $gap }
        $btnApproveDeletePreview.Location = New-Object System.Drawing.Point($xApprove, $y)

        $xCancel = $xApprove - $gap - $cancelW
        if ($xCancel -lt ($margin + $removeW + $gap)) { $xCancel = $margin + $removeW + $gap }
        $btnCancelDeletePreview.Location = New-Object System.Drawing.Point($xCancel, $y)
    }

    $resizeDeleteColumns = {
        $w0 = 260
        $w1 = 110
        $remaining = $lvDeletePreview.ClientSize.Width - $w0 - $w1 - 6
        $w2 = [int][Math]::Max(220, $remaining)
        $lvDeletePreview.Columns[0].Width = $w0
        $lvDeletePreview.Columns[1].Width = $w1
        $lvDeletePreview.Columns[2].Width = $w2
    }

    $layoutDeletePreviewSplit = {
        $w = [int]$splitDeletePreview.Width
        if ($w -le 0) { return }

        $desiredP1 = 430
        $desiredP2 = 260

        # Clamp min sizes against current width so SplitContainer constraints stay valid.
        $panel1Min = [int][Math]::Min($desiredP1, [Math]::Max(0, $w - $desiredP2))
        $panel2Min = [int][Math]::Min($desiredP2, [Math]::Max(0, $w - $panel1Min))

        if ($splitDeletePreview.Panel1MinSize -ne $panel1Min) { $splitDeletePreview.Panel1MinSize = $panel1Min }
        if ($splitDeletePreview.Panel2MinSize -ne $panel2Min) { $splitDeletePreview.Panel2MinSize = $panel2Min }

        $maxDistance = [int][Math]::Max($panel1Min, $w - $panel2Min)
        $targetDistance = [int][Math]::Min(700, $maxDistance)
        if ($targetDistance -lt $panel1Min) { $targetDistance = $panel1Min }
        if ($splitDeletePreview.SplitterDistance -ne $targetDistance) { $splitDeletePreview.SplitterDistance = $targetDistance }
    }

    $previewThumbCache = @{}

    $updateSummary = {
        $totalSize = [long]0
        foreach ($f in @($workingTargets)) {
            try { $totalSize += [long]$f.Length } catch { }
        }
        $srcText = if ([string]::IsNullOrWhiteSpace($SourceLabel)) {
            ""
        }
        else {
            "  |  $(T 'delete_preview_source_label'): $SourceLabel"
        }
        $lblSummary.Text = T 'delete_preview_summary' @($workingTargets.Count, (Format-Size $totalSize), $srcText)
        $btnApproveDeletePreview.Enabled = ($workingTargets.Count -gt 0)
    }

    $updateSelectedPreview = {
        if ($lvDeletePreview.SelectedItems.Count -eq 0) {
            $picDeletePreview.Image = $null
            $lblPreviewInfo1.Text = T 'delete_preview_none_selected'
            $lblPreviewInfo2.Text = ""
            $lblPreviewInfo3.Text = ""
            $btnRemoveFromDeleteList.Enabled = $false
            return
        }

        $selIdx = [int]$lvDeletePreview.SelectedItems[0].Tag
        if ($selIdx -lt 0 -or $selIdx -ge $workingTargets.Count) {
            $picDeletePreview.Image = $null
            $lblPreviewInfo1.Text = T 'delete_preview_none_selected'
            $lblPreviewInfo2.Text = ""
            $lblPreviewInfo3.Text = ""
            $btnRemoveFromDeleteList.Enabled = $false
            return
        }

        $f = $workingTargets[$selIdx]
        $fp = [string]$f.FullName
        $nm = [string]$f.Name
        $tp = Get-MediaTypeLabel (Get-MediaType $f.Extension)
        $lenText = Format-Size ([long]$f.Length)
        $lblPreviewInfo1.Text = $nm
        $lblPreviewInfo2.Text = "$tp  |  $lenText"
        $lblPreviewInfo3.Text = [string]$f.DirectoryName
        $btnRemoveFromDeleteList.Enabled = ($lvDeletePreview.SelectedItems.Count -gt 0)

        $pvW = [Math]::Max(220, $picDeletePreview.ClientSize.Width - 10)
        $pvH = [Math]::Max(180, $picDeletePreview.ClientSize.Height - 10)
        $thumbKey = "$fp|${pvW}x${pvH}"

        if ($previewThumbCache.ContainsKey($thumbKey)) {
            $picDeletePreview.Image = $previewThumbCache[$thumbKey]
            return
        }

        try {
            $img = Make-Thumb -Path $fp -W $pvW -H $pvH
            if ($img) {
                $previewThumbCache[$thumbKey] = $img
                $picDeletePreview.Image = $img
            }
            else {
                $picDeletePreview.Image = $null
            }
        }
        catch {
            $picDeletePreview.Image = $null
        }
    }

    $refreshDeleteList = {
        $selectedPaths = @()
        foreach ($si in @($lvDeletePreview.SelectedItems)) {
            $ix = [int]$si.Tag
            if ($ix -lt 0 -or $ix -ge $workingTargets.Count) { continue }
            $selectedPaths += [string]$workingTargets[$ix].FullName
        }
        if ($selectedPaths.Count -eq 0 -and $lvDeletePreview.Items.Count -gt 0) {
            $firstIx = [int]$lvDeletePreview.Items[0].Tag
            if ($firstIx -ge 0 -and $firstIx -lt $workingTargets.Count) {
                $selectedPaths += [string]$workingTargets[$firstIx].FullName
            }
        }

        $lvDeletePreview.BeginUpdate()
        try {
            $lvDeletePreview.Items.Clear()
            for ($i = 0; $i -lt $workingTargets.Count; $i++) {
                $f = $workingTargets[$i]
                $nm = try { [string]$f.Name } catch { T 'unknown_name' }
                $len = try { [long]$f.Length } catch { [long]0 }
                $dir = try { [string]$f.DirectoryName } catch { "" }

                $it = New-Object System.Windows.Forms.ListViewItem($nm)
                [void]$it.SubItems.Add((Format-Size $len))
                [void]$it.SubItems.Add($dir)
                $it.Tag = $i
                [void]$lvDeletePreview.Items.Add($it)
            }

            if ($selectedPaths.Count -gt 0) {
                foreach ($it in @($lvDeletePreview.Items)) {
                    $ix = [int]$it.Tag
                    if ($ix -lt 0 -or $ix -ge $workingTargets.Count) { continue }
                    $path = [string]$workingTargets[$ix].FullName
                    if ($selectedPaths -contains $path) { $it.Selected = $true }
                }
            }

            if ($lvDeletePreview.SelectedItems.Count -eq 0 -and $lvDeletePreview.Items.Count -gt 0) {
                $lvDeletePreview.Items[0].Selected = $true
            }
        }
        finally {
            $lvDeletePreview.EndUpdate()
        }

        & $updateSummary
        & $resizeDeleteColumns
        & $updateSelectedPreview
    }

    $removeSelectedFromList = {
        if ($lvDeletePreview.SelectedIndices.Count -eq 0) { return }

        $idxToRemove = @()
        foreach ($ix in @($lvDeletePreview.SelectedIndices)) {
            $idxToRemove += [int]$ix
        }

        $idxToRemove = @($idxToRemove | Sort-Object -Descending)
        foreach ($ix in $idxToRemove) {
            if ($ix -lt 0 -or $ix -ge $workingTargets.Count) { continue }
            $workingTargets.RemoveAt($ix)
        }

        & $refreshDeleteList
    }

    $approved = $false
    $btnApproveDeletePreview.Add_Click({
        if ($workingTargets.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show((T 'delete_preview_empty'), (T 'title_info'), 'OK', 'Information') | Out-Null
            return
        }
        $approved = $true
        $dlg.Close()
    })
    $btnCancelDeletePreview.Add_Click({ $dlg.Close() })
    $btnRemoveFromDeleteList.Add_Click({ & $removeSelectedFromList })

    $pBottom.Add_Resize({ & $layoutDeletePreviewButtons })
    $splitDeletePreview.Add_SizeChanged({ & $layoutDeletePreviewSplit })
    $lvDeletePreview.Add_Resize({ & $resizeDeleteColumns })
    $lvDeletePreview.Add_SelectedIndexChanged({ & $updateSelectedPreview })
    $lvDeletePreview.Add_KeyDown({
        if ($_.KeyCode -eq 'Delete') {
            & $removeSelectedFromList
            $_.Handled = $true
            return
        }
    })
    $dlg.Add_KeyDown({
        if ($_.KeyCode -eq 'Delete') {
            & $removeSelectedFromList
            $_.Handled = $true
            return
        }
    })
    $picDeletePreview.Add_Resize({ & $updateSelectedPreview })
    $dlg.Add_Shown({
        & $layoutDeletePreviewSplit
        & $layoutDeletePreviewButtons
        & $refreshDeleteList
        $btnApproveDeletePreview.Focus()
    })

    if ($form -and -not $form.IsDisposed) {
        [void]$dlg.ShowDialog($form)
    }
    else {
        [void]$dlg.ShowDialog()
    }
    $dlg.Dispose()

    $result = [pscustomobject]@{
        Approved = $approved
        Files = @($workingTargets)
    }
    return $result
}

function Invoke-DeleteFiles([object[]]$FilesToDelete, [string]$SourceLabel, [switch]$SkipConfirmation) {
    $targets = [System.Collections.ArrayList]::new()
    $seen = @{}

    foreach ($f in @($FilesToDelete)) {
        if (-not $f) { continue }
        $p = $f.FullName
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($seen.ContainsKey($p)) { continue }
        $seen[$p] = $true
        [void]$targets.Add($f)
    }

    if ($targets.Count -eq 0) { return $false }

    $tsz = [long]0
    foreach ($f in $targets) {
        try { $tsz += [long]$f.Length } catch { }
    }

    if (-not $SkipConfirmation) {
        $sample = [System.Collections.ArrayList]::new()
        $limit = [Math]::Min(12, $targets.Count)
        for ($i = 0; $i -lt $limit; $i++) {
            $fi = $targets[$i]
            [void]$sample.Add(" - $($fi.Name)")
        }
        if ($targets.Count -gt $limit) {
            [void]$sample.Add((T 'delete_confirm_more_files' @($targets.Count - $limit)))
        }
        $sampleText = if ($sample.Count -gt 0) {
            "`n`n$(T 'delete_confirm_examples_header')`n$($sample -join "`n")"
        }
        else {
            ""
        }
        $srcText = if ([string]::IsNullOrWhiteSpace($SourceLabel)) {
            ""
        }
        else {
            "`n$(T 'delete_confirm_source' @($SourceLabel))"
        }

        $msg = T 'delete_confirm_message' @($targets.Count, (Format-Size $tsz), $sampleText, $srcText)
        $r = [System.Windows.Forms.MessageBox]::Show($msg, (T 'title_warning'), 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return $false }
    }

    $lblStatus.Text = T 'delete_status_deleting'
    $form.Cursor = 'WaitCursor'
    [System.Windows.Forms.Application]::DoEvents()

    Ensure-RecycleBinType

    $deleted = 0
    $errs = 0
    $delPaths = [System.Collections.ArrayList]::new()

    foreach ($f in $targets) {
        $path = $f.FullName
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (-not (Test-Path -LiteralPath $path)) { continue }

        try {
            $result = [RecycleBin]::SendToRecycleBin($path)
            if ($result -eq 0) {
                $deleted++
                [void]$delPaths.Add($path)
            }
            else {
                $errs++
            }
        }
        catch {
            try {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                $deleted++
                [void]$delPaths.Add($path)
            }
            catch {
                $errs++
            }
        }
    }

    $form.Cursor = 'Default'
    $errMsg = if ($errs -gt 0) { T 'delete_status_error_suffix' @($errs) } else { "" }
    $lblStatus.Text = T 'delete_status_done' @($deleted, $errMsg)
    [System.Windows.Forms.MessageBox]::Show((T 'delete_done_message' @($deleted, $targets.Count)), (T 'title_completed'), 'OK', 'Information') | Out-Null

    if ($delPaths.Count -gt 0) {
        $deletedArray = @($delPaths)
        Remove-FromScannedMediaFiles $deletedArray

        $newDup = @{}
        foreach ($h in $script:Duplicates.Keys) {
            $rem = @($script:Duplicates[$h] | Where-Object { $deletedArray -notcontains $_.FullName })
            if ($rem.Count -gt 1) { $newDup[$h] = $rem }
        }
        $script:Duplicates = $newDup
        $script:MediaViewCache = @{}
        $script:PathToImageIndex = @{}
        $script:ModeRenderCache = @{}
        Fill-List
    }
    else {
        Update-Info
        Set-FilterButtonsEnabled ($lv.Items.Count -gt 0)
    }

    return ($deleted -gt 0)
}

function Start-SwipeReview {
    if ($script:IsListBuilding) {
        $lblStatus.Text = "$($script:PostBuildStatus) | $(T 'status_wait_build_swipe')"
        return
    }

    if ($script:ScannedMediaFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((T 'swipe_need_scan'), (T 'title_info'), 'OK', 'Information') | Out-Null
        return
    }

    $reviewItems = [System.Collections.ArrayList]::new()
    foreach ($f in @($script:ScannedMediaFiles)) {
        if (-not $f) { continue }
        $p = $f.FullName
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not (Test-Path -LiteralPath $p)) { continue }
        [void]$reviewItems.Add($f)
    }

    if ($reviewItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((T 'swipe_no_media'), (T 'title_info'), 'OK', 'Information') | Out-Null
        return
    }

    $statusBase = Get-StatusBase $lblStatus.Text
    $lblStatus.Text = "$statusBase | $(T 'status_opening_swipe')"

    $reviewForm = New-Object System.Windows.Forms.Form
    $reviewForm.Text = T 'swipe_mode_title'
    $reviewForm.Size = New-Object System.Drawing.Size(980, 700)
    $reviewForm.StartPosition = 'CenterParent'
    $reviewForm.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 30)
    $reviewForm.ForeColor = [System.Drawing.Color]::White
    $reviewForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $reviewForm.KeyPreview = $true
    $reviewForm.MinimumSize = New-Object System.Drawing.Size(820, 560)

    $pTop = New-Object System.Windows.Forms.Panel
    $pTop.Dock = 'Top'
    $pTop.Height = 88
    $pTop.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 42)

    $lblStep = New-Object System.Windows.Forms.Label
    $lblStep.Text = T 'swipe_card_progress' @(0, 0)
    $lblStep.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblStep.ForeColor = [System.Drawing.Color]::FromArgb(120, 200, 255)
    $lblStep.Location = New-Object System.Drawing.Point(14, 10)
    $lblStep.AutoSize = $true
    $pTop.Controls.Add($lblStep)

    $lblCounts = New-Object System.Windows.Forms.Label
    $lblCounts.Text = T 'swipe_counts'
    $lblCounts.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
    $lblCounts.Location = New-Object System.Drawing.Point(14, 34)
    $lblCounts.Size = New-Object System.Drawing.Size(500, 18)
    $lblCounts.AutoEllipsis = $true
    $pTop.Controls.Add($lblCounts)

    $lblCurrentDecision = New-Object System.Windows.Forms.Label
    $lblCurrentDecision.Text = T 'swipe_decision_waiting'
    $lblCurrentDecision.Font = New-Object System.Drawing.Font("Segoe UI", 8.8, [System.Drawing.FontStyle]::Bold)
    $lblCurrentDecision.ForeColor = [System.Drawing.Color]::White
    $lblCurrentDecision.BackColor = [System.Drawing.Color]::FromArgb(78, 78, 92)
    $lblCurrentDecision.TextAlign = 'MiddleCenter'
    $lblCurrentDecision.Size = New-Object System.Drawing.Size(280, 24)
    $lblCurrentDecision.Location = New-Object System.Drawing.Point(684, 10)
    $lblCurrentDecision.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $pTop.Controls.Add($lblCurrentDecision)

    $lblInfoReview = New-Object System.Windows.Forms.Label
    $lblInfoReview.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 190)
    $lblInfoReview.Location = New-Object System.Drawing.Point(14, 54)
    $lblInfoReview.Size = New-Object System.Drawing.Size(940, 26)
    $lblInfoReview.AutoEllipsis = $true
    $pTop.Controls.Add($lblInfoReview)

    $picReview = New-Object System.Windows.Forms.PictureBox
    $picReview.Dock = 'Fill'
    $picReview.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $picReview.SizeMode = 'Zoom'
    $reviewForm.Controls.Add($picReview)
    $reviewForm.Controls.Add($pTop)

    $pBottom = New-Object System.Windows.Forms.Panel
    $pBottom.Dock = 'Bottom'
    $pBottom.Height = 96
    $pBottom.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 42)
    $reviewForm.Controls.Add($pBottom)

    $btnPrevCard = New-Object System.Windows.Forms.Button
    $btnPrevCard.Text = T 'swipe_prev'
    $btnPrevCard.Size = New-Object System.Drawing.Size(130, 66)
    $btnPrevCard.Location = New-Object System.Drawing.Point(14, 15)
    $btnPrevCard.FlatStyle = 'Flat'
    $btnPrevCard.FlatAppearance.BorderSize = 0
    $btnPrevCard.BackColor = [System.Drawing.Color]::FromArgb(80, 85, 95)
    $btnPrevCard.ForeColor = [System.Drawing.Color]::White
    $btnPrevCard.Cursor = 'Hand'
    $pBottom.Controls.Add($btnPrevCard)

    $btnDeleteCard = New-Object System.Windows.Forms.Button
    $btnDeleteCard.Text = T 'swipe_delete'
    $btnDeleteCard.Size = New-Object System.Drawing.Size(200, 66)
    $btnDeleteCard.Location = New-Object System.Drawing.Point(176, 15)
    $btnDeleteCard.FlatStyle = 'Flat'
    $btnDeleteCard.FlatAppearance.BorderSize = 0
    $btnDeleteCard.BackColor = [System.Drawing.Color]::FromArgb(195, 55, 55)
    $btnDeleteCard.ForeColor = [System.Drawing.Color]::White
    $btnDeleteCard.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnDeleteCard.Cursor = 'Hand'
    $pBottom.Controls.Add($btnDeleteCard)

    $btnSkipCard = New-Object System.Windows.Forms.Button
    $btnSkipCard.Text = T 'swipe_skip'
    $btnSkipCard.Size = New-Object System.Drawing.Size(130, 66)
    $btnSkipCard.Location = New-Object System.Drawing.Point(408, 15)
    $btnSkipCard.FlatStyle = 'Flat'
    $btnSkipCard.FlatAppearance.BorderSize = 0
    $btnSkipCard.BackColor = [System.Drawing.Color]::FromArgb(110, 110, 120)
    $btnSkipCard.ForeColor = [System.Drawing.Color]::White
    $btnSkipCard.Cursor = 'Hand'
    $pBottom.Controls.Add($btnSkipCard)

    $btnKeepCard = New-Object System.Windows.Forms.Button
    $btnKeepCard.Text = T 'swipe_keep'
    $btnKeepCard.Size = New-Object System.Drawing.Size(200, 66)
    $btnKeepCard.Location = New-Object System.Drawing.Point(570, 15)
    $btnKeepCard.FlatStyle = 'Flat'
    $btnKeepCard.FlatAppearance.BorderSize = 0
    $btnKeepCard.BackColor = [System.Drawing.Color]::FromArgb(45, 165, 90)
    $btnKeepCard.ForeColor = [System.Drawing.Color]::White
    $btnKeepCard.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $btnKeepCard.Cursor = 'Hand'
    $pBottom.Controls.Add($btnKeepCard)

    $btnCancelReview = New-Object System.Windows.Forms.Button
    $btnCancelReview.Text = T 'swipe_cancel'
    $btnCancelReview.Size = New-Object System.Drawing.Size(130, 66)
    $btnCancelReview.Location = New-Object System.Drawing.Point(804, 15)
    $btnCancelReview.FlatStyle = 'Flat'
    $btnCancelReview.FlatAppearance.BorderSize = 0
    $btnCancelReview.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 82)
    $btnCancelReview.ForeColor = [System.Drawing.Color]::White
    $btnCancelReview.Cursor = 'Hand'
    $pBottom.Controls.Add($btnCancelReview)

    $btnFinishReview = New-Object System.Windows.Forms.Button
    $btnFinishReview.Text = T 'swipe_finish'
    $btnFinishReview.Size = New-Object System.Drawing.Size(130, 66)
    $btnFinishReview.Location = New-Object System.Drawing.Point(666, 15)
    $btnFinishReview.FlatStyle = 'Flat'
    $btnFinishReview.FlatAppearance.BorderSize = 0
    $btnFinishReview.BackColor = [System.Drawing.Color]::FromArgb(58, 110, 200)
    $btnFinishReview.ForeColor = [System.Drawing.Color]::White
    $btnFinishReview.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
    $btnFinishReview.Cursor = 'Hand'
    $pBottom.Controls.Add($btnFinishReview)

    $state = [pscustomobject]@{
        Index = 0
        Completed = $false
        EndedEarly = $false
        Decisions = @{}
        KeepCount = 0
        DeleteCount = 0
    }

    $reviewThumbCache = @{}

    $layoutButtons = {
        $margin = 14
        $gap = 8
        $y = 15
        $h = 66

        $prevW = 110
        $skipW = 110
        $finishW = 110
        $cancelW = 110

        $free = $pBottom.ClientSize.Width - ($margin * 2) - $prevW - $skipW - $finishW - $cancelW - ($gap * 5)
        $actionW = [int][Math]::Max(140, [Math]::Floor($free / 2))

        $x = $margin
        $btnPrevCard.Bounds = New-Object System.Drawing.Rectangle($x, $y, $prevW, $h)
        $x += $prevW + $gap

        $btnDeleteCard.Bounds = New-Object System.Drawing.Rectangle($x, $y, $actionW, $h)
        $x += $actionW + $gap

        $btnSkipCard.Bounds = New-Object System.Drawing.Rectangle($x, $y, $skipW, $h)
        $x += $skipW + $gap

        $btnKeepCard.Bounds = New-Object System.Drawing.Rectangle($x, $y, $actionW, $h)
        $x += $actionW + $gap

        $btnFinishReview.Bounds = New-Object System.Drawing.Rectangle($x, $y, $finishW, $h)
        $x += $finishW + $gap

        $btnCancelReview.Bounds = New-Object System.Drawing.Rectangle($x, $y, $cancelW, $h)
    }

    $updateCounts = {
        $markedCount = $state.Decisions.Count
        $lblCounts.Text = T 'swipe_counts_full' @($state.DeleteCount, $state.KeepCount, $markedCount, $reviewItems.Count)
    }

    $updateDecisionBadge = {
        param([string]$Decision)

        switch ($Decision) {
            "keep" {
                $lblCurrentDecision.Text = T 'swipe_decision_keep'
                $lblCurrentDecision.BackColor = [System.Drawing.Color]::FromArgb(45, 165, 90)
            }
            "delete" {
                $lblCurrentDecision.Text = T 'swipe_decision_delete'
                $lblCurrentDecision.BackColor = [System.Drawing.Color]::FromArgb(195, 55, 55)
            }
            default {
                $lblCurrentDecision.Text = T 'swipe_decision_waiting'
                $lblCurrentDecision.BackColor = [System.Drawing.Color]::FromArgb(78, 78, 92)
            }
        }
    }

    $setDecision = {
        param([string]$Path, [string]$Decision)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }

        if ($state.Decisions.ContainsKey($Path)) {
            switch ($state.Decisions[$Path]) {
                "keep" { $state.KeepCount = [Math]::Max(0, $state.KeepCount - 1) }
                "delete" { $state.DeleteCount = [Math]::Max(0, $state.DeleteCount - 1) }
            }
        }

        $state.Decisions[$Path] = $Decision
        switch ($Decision) {
            "keep" { $state.KeepCount++ }
            "delete" { $state.DeleteCount++ }
        }

        & $updateCounts
    }

    $showCurrent = {
        if ($state.Index -lt 0) { $state.Index = 0 }
        if ($state.Index -ge $reviewItems.Count) {
            $state.EndedEarly = $false
            $state.Completed = $true
            $reviewForm.Close()
            return
        }

        $cur = $reviewItems[$state.Index]
        $tp = Get-MediaTypeLabel (Get-MediaType $cur.Extension)
        $lblStep.Text = T 'swipe_card_progress' @(($state.Index + 1), $reviewItems.Count)
        $lblInfoReview.Text = "$($cur.Name)  |  $tp  |  $(Format-Size $cur.Length)  |  $($cur.DirectoryName)"

        $previewW = [Math]::Max(420, $picReview.ClientSize.Width - 24)
        $previewH = [Math]::Max(280, $picReview.ClientSize.Height - 24)
        $thumbKey = "$($cur.FullName)|${previewW}x${previewH}"
        if ($reviewThumbCache.ContainsKey($thumbKey)) {
            $picReview.Image = $reviewThumbCache[$thumbKey]
        }
        else {
            try {
                $img = Make-Thumb -Path $cur.FullName -W $previewW -H $previewH
                $reviewThumbCache[$thumbKey] = $img
                $picReview.Image = $img
            }
            catch {
                $picReview.Image = $null
            }
        }

        $tag = T 'swipe_tag_waiting'
        $currentDecision = ""
        if ($state.Decisions.ContainsKey($cur.FullName)) {
            $currentDecision = [string]$state.Decisions[$cur.FullName]
            switch ($currentDecision) {
                "keep" { $tag = T 'swipe_tag_keep' }
                "delete" { $tag = T 'swipe_tag_delete' }
            }
        }
        & $updateDecisionBadge $currentDecision
        $reviewForm.Text = "$(T 'swipe_mode_title')  -  $tag"

        $btnPrevCard.Enabled = ($state.Index -gt 0)
    }

    $goNextWithDecision = {
        param([string]$Decision)
        if ($state.Index -lt 0 -or $state.Index -ge $reviewItems.Count) { return }
        $cur = $reviewItems[$state.Index]
        & $setDecision $cur.FullName $Decision
        $state.Index++
        & $showCurrent
    }

    $goPrev = {
        if ($state.Index -le 0) { return }
        $state.Index--
        & $showCurrent
    }

    $goNext = {
        if ($state.Index -lt 0 -or $state.Index -ge $reviewItems.Count) { return }
        $state.Index++
        & $showCurrent
    }

    $finishReview = {
        if ($state.Index -lt $reviewItems.Count) {
            $r = [System.Windows.Forms.MessageBox]::Show((T 'swipe_early_finish_question'), (T 'swipe_early_finish_title'), 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            $state.EndedEarly = $true
        }
        else {
            $state.EndedEarly = $false
        }

        $state.Completed = $true
        $reviewForm.Close()
    }

    $btnDeleteCard.Add_Click({ & $goNextWithDecision "delete" })
    $btnKeepCard.Add_Click({ & $goNextWithDecision "keep" })
    $btnSkipCard.Add_Click({ & $goNext })
    $btnPrevCard.Add_Click({ & $goPrev })
    $btnFinishReview.Add_Click({ & $finishReview })
    $btnCancelReview.Add_Click({ $reviewForm.Close() })

    $reviewForm.Add_KeyDown({
        if ($_.KeyCode -eq 'Left' -or $_.KeyCode -eq 'A') {
            & $goNextWithDecision "delete"
            $_.Handled = $true
            return
        }
        if ($_.KeyCode -eq 'Right' -or $_.KeyCode -eq 'D' -or $_.KeyCode -eq 'Enter') {
            & $goNextWithDecision "keep"
            $_.Handled = $true
            return
        }
        if ($_.KeyCode -eq 'Space') {
            & $goNext
            $_.Handled = $true
            return
        }
        if ($_.KeyCode -eq 'Back') {
            & $goPrev
            $_.Handled = $true
            return
        }
        if ($_.KeyCode -eq 'Escape') {
            $reviewForm.Close()
            $_.Handled = $true
            return
        }
        if ($_.KeyCode -eq 'F') {
            & $finishReview
            $_.Handled = $true
            return
        }
    })

    $reviewForm.Add_FormClosing({
        param($sender, $e)
        if ($state.Completed) { return }
        $r = [System.Windows.Forms.MessageBox]::Show((T 'swipe_close_confirm'), (T 'title_confirm'), 'YesNo', 'Question')
        if ($r -ne 'Yes') { $e.Cancel = $true }
    })

    $reviewForm.Add_Shown({
        & $layoutButtons
        & $updateCounts
        & $showCurrent
    })

    $pBottom.Add_Resize({ & $layoutButtons })

    [void]$reviewForm.ShowDialog($form)
    $reviewForm.Dispose()

    if (-not $state.Completed) {
        $lblStatus.Text = "$statusBase | $(T 'status_swipe_cancelled')"
        return
    }

    $finishLabel = if ($state.EndedEarly) { T 'swipe_finished_early' } else { T 'swipe_finished_done' }

    $deleteSet = @{}
    foreach ($p in $state.Decisions.Keys) {
        if ($state.Decisions[$p] -eq "delete") {
            $deleteSet[$p] = $true
        }
    }

    if ($deleteSet.Count -eq 0) {
        $lblStatus.Text = "$statusBase | $(T 'swipe_status_no_delete' @($finishLabel))"
        [System.Windows.Forms.MessageBox]::Show((T 'swipe_no_delete_selection' @($finishLabel)), (T 'title_info'), 'OK', 'Information') | Out-Null
        return
    }

    $lblStatus.Text = "$statusBase | $(T 'swipe_status_summary' @($finishLabel, $deleteSet.Count, $state.KeepCount))"

    $toDelete = [System.Collections.ArrayList]::new()
    foreach ($f in $reviewItems) {
        if ($deleteSet.ContainsKey($f.FullName)) {
            [void]$toDelete.Add($f)
        }
    }

    $deleteReview = Show-DeletePreviewDialog -FilesToDelete @($toDelete) -Title $finishLabel -SourceLabel (T 'swipe_delete_review_source')
    if (-not $deleteReview -or -not $deleteReview.Approved) {
        $lblStatus.Text = "$statusBase | $(T 'swipe_delete_cancelled' @($finishLabel))"
        return
    }

    $finalDelete = @($deleteReview.Files)
    if ($finalDelete.Count -eq 0) {
        $lblStatus.Text = "$statusBase | $(T 'swipe_delete_no_remaining' @($finishLabel))"
        [System.Windows.Forms.MessageBox]::Show((T 'swipe_delete_empty_after_review'), (T 'title_info'), 'OK', 'Information') | Out-Null
        return
    }

    $lblStatus.Text = "$statusBase | $(T 'swipe_status_summary' @($finishLabel, $finalDelete.Count, $state.KeepCount))"
    [void](Invoke-DeleteFiles -FilesToDelete $finalDelete -SourceLabel (T 'swipe_delete_review_source') -SkipConfirmation)
}

function Do-Filter([string]$Mode) {
    if ($script:IsListBuilding) {
        $lblStatus.Text = "$($script:PostBuildStatus) | $(T 'status_wait_build_filter')"
        return
    }
    if ($Mode -eq "swipe_review") {
        Start-SwipeReview
        return
    }
    if ($lv.Items.Count -eq 0) { return }

    $script:ThumbTimer.Stop()
    $statusBase = Get-StatusBase $lblStatus.Text
    $lblStatus.Text = "$statusBase | $(T 'status_filter_applying')"
    [System.Windows.Forms.Application]::DoEvents()

    $cancelled = $false
    $checkSet = @{}

    if ($Mode -eq "specific_folder") {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = T 'filter_folder_prompt'
        if ($dlg.ShowDialog() -ne 'OK') {
            $cancelled = $true
        } else {
            $tf = $dlg.SelectedPath
            $folderHasOther = @{}
            foreach ($h in $script:Duplicates.Keys) {
                $grp = $script:Duplicates[$h]
                $hasInside = $false
                $hasOutside = $false
                foreach ($f in $grp) {
                    if ($f.DirectoryName.StartsWith($tf, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $hasInside = $true
                    } else {
                        $hasOutside = $true
                    }
                    if ($hasInside -and $hasOutside) { break }
                }
                $folderHasOther[$h] = ($hasInside -and $hasOutside)
            }

            foreach ($item in $lv.Items) {
                $f = $script:FlatList[[int]$item.Tag]
                if (-not $script:PathToHash.ContainsKey($f.FullName)) { continue }
                $h = $script:PathToHash[$f.FullName]
                if ($folderHasOther[$h] -and $f.DirectoryName.StartsWith($tf, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $checkSet[$f.FullName] = $true
                }
            }
        }
    }
    elseif ($Mode -eq "pick_one") {
        $viewData = Get-MediaViewData $script:CurrentMediaMode
        foreach ($g in $viewData.Groups) {
            $files = @($g.Files)
            if ($files.Count -le 1) { continue }
            $meta = if ($script:HashMeta.ContainsKey($g.Hash)) { $script:HashMeta[$g.Hash] } else { @{} }
            $pickPath = Get-OneStrategyKeepPath -meta $meta -files $files
            if ($pickPath) { $checkSet[$pickPath] = $true }
        }
    }
    elseif ($Mode -eq "leave_one") {
        $viewData = Get-MediaViewData $script:CurrentMediaMode
        foreach ($g in $viewData.Groups) {
            $files = @($g.Files)
            if ($files.Count -le 1) { continue }
            $meta = if ($script:HashMeta.ContainsKey($g.Hash)) { $script:HashMeta[$g.Hash] } else { @{} }
            $keepPath = Get-OneStrategyKeepPath -meta $meta -files $files
            if (-not $keepPath) { continue }
            foreach ($f in $files) {
                if ($f.FullName -ne $keepPath) { $checkSet[$f.FullName] = $true }
            }
        }
    }
    elseif ($Mode -ne "select_all" -and $Mode -ne "deselect_all") {
        $lblStatus.Text = $statusBase
        if ($script:UnloadedItems.Count -gt 0 -and -not $script:ThumbTimer.Enabled) {
            $script:ThumbTimer.Start()
        }
        return
    }

    if ($cancelled) {
        $lblStatus.Text = $statusBase
        if ($script:UnloadedItems.Count -gt 0 -and -not $script:ThumbTimer.Enabled) {
            $script:ThumbTimer.Start()
        }
        return
    }

    $script:IsBulkCheckUpdate = $true
    $lv.BeginUpdate()
    try {
        foreach ($item in $lv.Items) {
            $f = $script:FlatList[[int]$item.Tag]
            $shouldCheck = $false
            if ($Mode -eq "select_all") {
                $shouldCheck = $true
            }
            elseif ($Mode -eq "deselect_all") {
                $shouldCheck = $false
            }
            else {
                $shouldCheck = $checkSet.ContainsKey($f.FullName)
            }
            if ($item.Checked -ne $shouldCheck) {
                $item.Checked = $shouldCheck
            }
        }
    }
    finally {
        $lv.EndUpdate()
        $script:IsBulkCheckUpdate = $false
    }

    Update-Info
    $lblStatus.Text = $statusBase
    if ($script:UnloadedItems.Count -gt 0 -and -not $script:ThumbTimer.Enabled) {
        $script:ThumbTimer.Start()
    }
}

Apply-Language
Apply-ResponsiveLayout
$form.Add_Resize({ Apply-ResponsiveLayout })

# ==================== EVENTS ====================
if ($script:LanguageCombo) {
    $script:LanguageCombo.Add_SelectedIndexChanged({
        $newLang = if ($script:LanguageCombo.SelectedIndex -eq 0) { 'tr' } else { 'en' }
        if ($newLang -eq $script:CurrentLanguage) { return }

        $script:CurrentLanguage = $newLang
        Apply-Language
        Apply-ResponsiveLayout

        if ($script:Duplicates.Count -gt 0) {
            $script:MediaViewCache = @{}
            $script:ModeRenderCache = @{}
            Fill-List -FastViewSwitch
        }
        else {
            if ([string]::IsNullOrWhiteSpace($script:SelectedFolderPath)) {
                $lblStatus.Text = T 'status_ready'
            }
            else {
                $lblStatus.Text = T 'status_folder_selected' @($script:SelectedFolderPath)
            }
        }
    })
}

$btnFolder.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = T 'scan_folder_prompt'
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:SelectedFolderPath = $dlg.SelectedPath
        $lblPath.Text = $script:SelectedFolderPath
        $lblPath.ForeColor = [System.Drawing.Color]::FromArgb(140, 210, 255)
        $btnScan.Enabled = $true
        $lblStatus.Text = T 'status_folder_selected' @($script:SelectedFolderPath)
    }
})

$btnScan.Add_Click({
    $folder = $script:SelectedFolderPath
    if (-not (Test-Path $folder)) {
        [System.Windows.Forms.MessageBox]::Show((T 'error_invalid_folder'), (T 'title_error'), 'OK', 'Error')
        return
    }

    $script:ThumbTimer.Stop()
    $script:BuildTimer.Stop()
    $script:GroupThumbTimer.Stop()
    $script:IsListBuilding = $false
    $script:PendingGroupIndex = -1
    $script:BuildItems.Clear()
    $script:BuildIndex = 0
    $script:UnloadedItems.Clear()
    $script:PathToImageIndex = @{}
    $script:MediaViewCache = @{}
    $script:ModeRenderCache = @{}
    $script:ScannedMediaFiles = [System.Collections.ArrayList]::new()
    $script:CurrentMediaMode = "all"
    Set-FilterButtonsEnabled $false
    if ($script:MediaFilterCombo) { $script:MediaFilterCombo.Enabled = $false }
    $btnDelete.Enabled = $false

    $btnScan.Enabled = $false; $btnFolder.Enabled = $false
    $lv.Items.Clear(); $lv.Groups.Clear(); $imageList.Images.Clear()
    $progressBar.Visible = $true; $progressBar.Value = 0
    $lblStatus.Text = T 'status_scanning_files'
    $form.Cursor = 'WaitCursor'
    [System.Windows.Forms.Application]::DoEvents()

    $rec = $chkRecursive.Checked

    # 1. Dosyalari topla
    $files = [System.Collections.ArrayList]::new()
    Get-ChildItem -Path $folder -File -Recurse:$rec -ErrorAction SilentlyContinue | ForEach-Object {
        if ($script:AllExt -contains $_.Extension.ToLower()) { [void]$files.Add($_) }
    }

    $total = $files.Count
    foreach ($f in $files) { [void]$script:ScannedMediaFiles.Add($f) }
    $lblStatus.Text = T 'status_media_found' @($total)
    [System.Windows.Forms.Application]::DoEvents()

    if ($total -eq 0) {
        $lblStatus.Text = T 'status_no_media_found'
        $progressBar.Visible = $false
        $btnScan.Enabled = $true; $btnFolder.Enabled = $true; $form.Cursor = 'Default'
        return
    }

    # 2. Boyut gruplama
    $sizeMap = @{}
    foreach ($f in $files) {
        $key = $f.Length
        if (-not $sizeMap.ContainsKey($key)) { $sizeMap[$key] = [System.Collections.ArrayList]::new() }
        [void]$sizeMap[$key].Add($f)
    }
    $candidates = [System.Collections.ArrayList]::new()
    foreach ($key in $sizeMap.Keys) {
        if ($sizeMap[$key].Count -gt 1) {
            foreach ($f in $sizeMap[$key]) { [void]$candidates.Add($f) }
        }
    }

    if ($candidates.Count -eq 0) {
        $lblStatus.Text = T 'status_no_duplicates_found' @($total)
        $progressBar.Visible = $false
        $btnScan.Enabled = $true; $btnFolder.Enabled = $true; $form.Cursor = 'Default'
        Set-FilterButtonsEnabled $false
        return
    }

    # 3. Hizli hash (ilk 8KB)
    $lblStatus.Text = T 'status_fast_scan' @(0, $candidates.Count)
    $progressBar.Maximum = $candidates.Count
    [System.Windows.Forms.Application]::DoEvents()

    $fastHashMap = @{}
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $f = $candidates[$i]
        $progressBar.Value = $i + 1
        if ($i % 15 -eq 0) {
            $lblStatus.Text = T 'status_fast_scan' @(($i + 1), $candidates.Count)
            [System.Windows.Forms.Application]::DoEvents()
        }
        $h = Get-FastHash -Path $f.FullName -ByteCount 8192
        if ($h) {
            $key = "$($f.Length)_$h"
            if (-not $fastHashMap.ContainsKey($key)) { $fastHashMap[$key] = [System.Collections.ArrayList]::new() }
            [void]$fastHashMap[$key].Add($f)
        }
    }

    $finalCandidates = [System.Collections.ArrayList]::new()
    foreach ($key in $fastHashMap.Keys) {
        if ($fastHashMap[$key].Count -gt 1) {
            foreach ($f in $fastHashMap[$key]) { [void]$finalCandidates.Add($f) }
        }
    }

    if ($finalCandidates.Count -eq 0) {
        $lblStatus.Text = T 'status_no_duplicates_found' @($total)
        $progressBar.Visible = $false
        $btnScan.Enabled = $true; $btnFolder.Enabled = $true; $form.Cursor = 'Default'
        Set-FilterButtonsEnabled $false
        return
    }

    # 4. Tam hash
    $lblStatus.Text = T 'status_full_hash' @(0, $finalCandidates.Count)
    $progressBar.Maximum = $finalCandidates.Count
    $progressBar.Value = 0
    [System.Windows.Forms.Application]::DoEvents()

    $fullHashMap = @{}
    for ($i = 0; $i -lt $finalCandidates.Count; $i++) {
        $f = $finalCandidates[$i]
        $progressBar.Value = $i + 1
        if ($i % 5 -eq 0) {
            $lblStatus.Text = T 'status_full_hash' @(($i + 1), $finalCandidates.Count)
            [System.Windows.Forms.Application]::DoEvents()
        }
        $h = Get-FullHash -Path $f.FullName
        if ($h) {
            if (-not $fullHashMap.ContainsKey($h)) { $fullHashMap[$h] = [System.Collections.ArrayList]::new() }
            [void]$fullHashMap[$h].Add($f)
        }
    }

    $script:Duplicates = @{}
    foreach ($k in $fullHashMap.Keys) {
        if ($fullHashMap[$k].Count -gt 1) { $script:Duplicates[$k] = $fullHashMap[$k] }
    }
    $script:MediaViewCache = @{}
    $script:PathToImageIndex = @{}
    $script:ModeRenderCache = @{}

    $progressBar.Visible = $false
    $btnScan.Enabled = $true; $btnFolder.Enabled = $true; $form.Cursor = 'Default'

    if ($script:Duplicates.Count -eq 0) {
        $lblStatus.Text = T 'status_no_duplicates_found' @($total)
        Set-FilterButtonsEnabled $false
        return
    }

    $dupTotal = 0; $waste = [long]0
    foreach ($h in $script:Duplicates.Keys) {
        $fs = $script:Duplicates[$h]
        $dupTotal += $fs.Count
        $waste += $fs[0].Length * ($fs.Count - 1)
    }

    $lblStatus.Text = T 'status_scan_summary' @($script:Duplicates.Count, $dupTotal, (Format-Size $waste))
    [System.Windows.Forms.Application]::DoEvents()

    # Medya gorunum cache'lerini bir kez hazirla (sonraki tur degisimleri hizli olur)
    [void](Get-MediaViewData "all")
    [void](Get-MediaViewData "image")
    [void](Get-MediaViewData "video")
    [void](Get-MediaViewData "audio")

    Fill-List
})

$lv.Add_ItemChecked({
    if ($script:IsBulkCheckUpdate) { return }
    Update-Info
})

$lv.Add_SelectedIndexChanged({
    if ($lv.SelectedItems.Count -eq 0) {
        $script:PendingGroupIndex = -1
        $script:GroupThumbTimer.Stop()
        return
    }
    $ix = [int]$lv.SelectedItems[0].Tag
    if ($ix -lt 0 -or $ix -ge $script:FlatList.Count) { return }
    $f = $script:FlatList[$ix]

    $lblFN.Text = $f.Name
    $ext = $f.Extension.ToLower()
    $tp = Get-MediaTypeLabel (Get-MediaType $ext)
    $lblFI.Text = T 'details_template' @((Format-Size $f.Length), $tp, $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $f.DirectoryName)

    # Onizleme: oncelikle cache'den, yoksa kucuk thumb goster (buyuk preview lazy)
    $picPreview.Image = $null
    $ck120 = "$($f.FullName)|${THUMB_W}x${THUMB_H}"
    if ($script:ThumbCache.ContainsKey($ck120)) {
        $picPreview.Image = $script:ThumbCache[$ck120]
    }

    # Buyuk preview async timer ile yukle (handler sadece bir kez eklenir)
    if (-not $script:PreviewTimer) {
        $script:PreviewTimer = New-Object System.Windows.Forms.Timer
        $script:PreviewTimer.Interval = 50
        $script:PreviewTimer.Add_Tick({
            $script:PreviewTimer.Stop()
            $pth = $script:PreviewPath
            if (-not $pth) { return }
            try {
                $prvImg = Make-Thumb -Path $pth -W 260 -H 220
                if ($prvImg -and $script:PreviewPath -eq $pth) {
                    $picPreview.Image = $prvImg
                }
            } catch { }
        })
    }
    $script:PreviewPath = $f.FullName
    $script:PreviewTimer.Stop()
    $script:PreviewTimer.Start()

    $script:PendingGroupIndex = $ix
    $script:GroupThumbTimer.Stop()
    $script:GroupThumbTimer.Start()
})

# Scroll/resize tetikleyici: timer'i yeniden baslat
$lv.Add_MouseWheel({
    if ($script:UnloadedItems.Count -gt 0 -and -not $script:ThumbTimer.Enabled) {
        $script:ThumbTimer.Start()
    }
})

$lv.Add_Resize({
    if ($script:UnloadedItems.Count -gt 0 -and -not $script:ThumbTimer.Enabled) {
        $script:ThumbTimer.Start()
    }
})

$btnOpen.Add_Click({
    if ($lv.SelectedItems.Count -eq 0) { return }
    $ix = [int]$lv.SelectedItems[0].Tag
    if ($ix -ge 0 -and $ix -lt $script:FlatList.Count) {
        Start-Process $script:FlatList[$ix].FullName
    }
})

$btnOpenDir.Add_Click({
    if ($lv.SelectedItems.Count -eq 0) { return }
    $ix = [int]$lv.SelectedItems[0].Tag
    if ($ix -ge 0 -and $ix -lt $script:FlatList.Count) {
        $fp = $script:FlatList[$ix].FullName
        Start-Process explorer.exe -ArgumentList "/select,`"$fp`""
    }
})

foreach ($b in $filterButtons) {
    $b.Add_Click({ Do-Filter $this.Tag })
}

if ($script:MediaFilterCombo) {
    $script:MediaFilterCombo.Add_SelectedIndexChanged({
        if ($script:IsListBuilding) { return }
        if (-not $script:Duplicates -or $script:Duplicates.Count -eq 0) { return }
        $newMode = Get-MediaFilterMode
        if ($newMode -eq $script:CurrentMediaMode) { return }
        Fill-List -FastViewSwitch
    })
}

$btnDelete.Add_Click({
    $checked = @($lv.CheckedItems)
    if ($checked.Count -eq 0) { return }

    $targets = [System.Collections.ArrayList]::new()
    foreach ($ci in $checked) {
        $ix = [int]$ci.Tag
        if ($ix -lt 0 -or $ix -ge $script:FlatList.Count) { continue }
        [void]$targets.Add($script:FlatList[$ix])
    }

    [void](Invoke-DeleteFiles -FilesToDelete @($targets) -SourceLabel "Listeden secilenler")
})

# ==================== GOSTER ====================
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
$form.Dispose()
