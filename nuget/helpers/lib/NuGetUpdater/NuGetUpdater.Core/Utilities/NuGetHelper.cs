namespace NuGetUpdater.Core;

internal static class NuGetHelper
{
    internal static async Task<bool> DownloadNuGetPackagesAsync(string repoRoot, string projectPath, IReadOnlyCollection<Dependency> packages, ILogger logger)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("msbuild_sdk_restore_");
        try
        {
            var tempProjectPath = await MSBuildHelper.CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, "netstandard2.0", packages, logger, usePackageDownload: true);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["restore", tempProjectPath], tempDirectory.FullName);

            return exitCode == 0;
        }
        finally
        {
            tempDirectory.Delete(recursive: true);
        }
    }
}
